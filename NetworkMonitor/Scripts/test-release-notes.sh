#!/bin/bash
# 发布说明生成器回归 —— 断言「能点、不点名别人」
#
# 背景：v1.27.0 的 Release 正文里
#   ① 唯一的「完整变更」链接指向 bsfeng/toolbar（本仓 origin 是 codeup），打开是 404；
#   ② 逐条提交只有反引号里的短 hash，一行都点不进去；
#   ③ 提交标题里的 @Sendable 被 GitHub 渲染成组织提及，页脚凭空多出一个「贡献者 sendable」。
# 三条都是「发出去才发现」，因此固化成断言：脚本改动先在这里红，不要等到发布后手改正文。
#
# 用法：bash NetworkMonitor/Scripts/test-release-notes.sh
# 纯只读：只读 git 历史与脚本自身，临时产物落在 mktemp 目录并自动清理。

set -uo pipefail

cd "$(dirname "$0")/.."

SCRIPT="Scripts/generate-release-notes.sh"
REPO="baosfeng/toolbar"
temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT

failures=0
pass() { printf '✅ %s\n' "$1"; }
fail() { printf '❌ %s\n' "$1"; failures=$((failures + 1)); }

check_contains() {
    local label="$1" needle="$2" haystack="$3"
    if printf '%s' "$haystack" | grep -qF -- "$needle"; then
        pass "$label"
    else
        fail "$label（找不到：$needle）"
    fi
}

check_absent() {
    local label="$1" needle="$2" haystack="$3"
    if printf '%s' "$haystack" | grep -qF -- "$needle"; then
        fail "$label（不该出现：$needle）"
    else
        pass "$label"
    fi
}

[ -f "$SCRIPT" ] || { echo "找不到 $SCRIPT" >&2; exit 1; }

# 取一个真实版本区间（有 tag 用 tag，否则退到 HEAD）
TAG=$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)
if [ -n "$TAG" ]; then
    PREV=$(git describe --tags --abbrev=0 --match 'v*' "$TAG^" 2>/dev/null || true)
else
    PREV=""
fi
if [ -n "$PREV" ]; then
    notes=$(bash "$SCRIPT" --tag "$TAG" --prev "$PREV" 2>&1)
    range="${PREV}..${TAG}"
else
    notes=$(bash "$SCRIPT" --tag HEAD 2>&1)
    range="全部历史"
fi

echo "回归区间：${range}"
echo

# ① 完整变更链接必须指向真实 GitHub 仓库（不能是 origin 的 codeup 用户名）
check_contains "完整变更链接指向 ${REPO}" "github.com/${REPO}/compare/" "$notes"
check_absent   "完整变更链接不指向 bsfeng（404 的那次）" "github.com/bsfeng/" "$notes"

# ② 逐条提交的短 hash 必须可点
check_contains "commit 链接指向 ${REPO}/commit" "github.com/${REPO}/commit/" "$notes"

# ③ @提及必须被中和成行内代码，否则 GitHub 会在页脚挂出假贡献者
mention_hits=$(printf '%s' "$notes" | grep -cE '(^|[^`A-Za-z0-9_.-])@[A-Za-z0-9_-]' || true)
if [ "$mention_hits" = "0" ]; then
    pass "没有会触发 GitHub 提及的裸 @"
else
    fail "没有会触发 GitHub 提及的裸 @（命中 ${mention_hits} 行）"
    printf '%s' "$notes" | grep -nE '(^|[^`A-Za-z0-9_.-])@[A-Za-z0-9_-]' | head -3 | sed 's/^/    /'
fi

# ④ 邮箱里的 @ 不能被误伤
neutralize_only=$(sed -n '/^neutralize_mentions() {/,/^}/p' "$SCRIPT")
if [ -n "$neutralize_only" ]; then
    printf '%s\n' "$neutralize_only" > "$temp_dir/fn.sh"
    . "$temp_dir/fn.sh"
    email_out=$(neutralize_mentions "联系 a@b.com 处理")
    if [ "$email_out" = "联系 a@b.com 处理" ]; then
        pass "邮箱里的 @ 不被误伤"
    else
        fail "邮箱里的 @ 不被误伤（实际输出：${email_out}）"
    fi
    at_out=$(neutralize_mentions "新增 @Sendable 相关踩坑")
    expected=$(printf '新增 `@Sendable` 相关踩坑')
    if [ "$at_out" = "$expected" ]; then
        pass "裸 @Sendable 被包成行内代码"
    else
        fail "裸 @Sendable 被包成行内代码（实际输出：${at_out}）"
    fi
else
    fail "脚本里找不到 neutralize_mentions"
fi

echo
if [ "$failures" -eq 0 ]; then
    echo "🎉 发布说明回归全部通过"
    exit 0
fi
echo "❌ 发布说明回归失败 ${failures} 项"
exit 1
