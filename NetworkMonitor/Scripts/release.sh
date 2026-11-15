#!/bin/bash
# release.sh —— 一站式发版：校验 → bump → 提交 → 推 → 打 tag → 跟到底
#
# 为什么要它：以前发版靠人记着「改两处版本号 + 打 tag + 看 CI」，连续踩了两次
# 「本机能编、CI 编不过」（any P! / effectIsInteractive），1.24.x / 1.25.0 / 1.26.0
# 全都因此没能发布。把人记的事交给脚本，并在动手前先过 CI 闸门。
#
# 用法：
#   Scripts/release.sh 1.28.0                # 真发版
#   Scripts/release.sh 1.28.0 --dry-run      # 只做检查，不改任何文件
#   Scripts/release.sh 1.28.0 --skip-ci-gate # 跳过 CI 闸门（不推荐）

set -euo pipefail

REPO="baosfeng/toolbar"
REMOTE="github"
BRANCH="main"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PROJECT_DIR/.." && pwd)"
PLIST_SOURCE="$PROJECT_DIR/Scripts/build-app.sh"
AGENTS_FILE="$REPO_ROOT/AGENTS.md"

VERSION=""
DRY_RUN=0
SKIP_CI=0

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --skip-ci-gate) SKIP_CI=1; shift ;;
        -h|--help) sed -n "2,13p" "$0"; exit 0 ;;
        -*) echo "未知参数：$1" >&2; exit 2 ;;
        *) VERSION="$1"; shift ;;
    esac
done

[ -n "$VERSION" ] || { echo "用法：Scripts/release.sh <版本号> [--dry-run] [--skip-ci-gate]" >&2; exit 2; }
case "$VERSION" in [0-9]*.[0-9]*.[0-9]*) ;; *) echo "版本号要形如 1.28.0，收到：$VERSION" >&2; exit 2 ;; esac

TAG="v$VERSION"
say() { echo "[release] $*"; }
fail() { echo "❌ $*" >&2; exit 1; }

say "1/6 检查工作区"
cd "$REPO_ROOT"
[ -z "$(git status --porcelain)" ] || fail "工作区不干净，先提交或 stash"
[ "$(git rev-parse --abbrev-ref HEAD)" = "$BRANCH" ] || fail "发版必须在 $BRANCH 上"

say "2/6 检查版本号"
old_version=$(grep -A1 "<key>CFBundleShortVersionString</key>" "$PLIST_SOURCE" | sed -n "s/.*<string>\(.*\)<\/string>.*/\1/p" | head -1)
old_build=$(grep -A1 "<key>CFBundleVersion</key>" "$PLIST_SOURCE" | sed -n "s/.*<string>\(.*\)<\/string>.*/\1/p" | head -1)
new_build=$((old_build + 1))
say "   当前 ${old_version}（构建号 ${old_build}）→ 目标 ${VERSION}（构建号 ${new_build}）"
[ "$old_version" = "$VERSION" ] && fail "版本号已经是 ${VERSION}"

# 语义化比较：逐段按数值比（字符串比会把 1.9 判成大于 1.10）
higher=$(python3 -c "
import sys
def parts(v): return [int(x) for x in v.split(".")[:3]]
old, new = parts(sys.argv[1]), parts(sys.argv[2])
print(1 if new > old else 0)
" "$old_version" "$VERSION")
[ "$higher" = "1" ] || fail "新版本号必须大于当前 $old_version"
git rev-parse -q --verify "refs/tags/$TAG" > /dev/null && fail "本地已有 tag $TAG"
git ls-remote --tags "$REMOTE" "refs/tags/$TAG" 2>/dev/null | grep -q . && fail "远端已有 tag $TAG"

if [ "$DRY_RUN" = "0" ]; then
    say "3/6 门禁与测试"
    ( cd "$PROJECT_DIR" && bash Scripts/check-file-size.sh )
    ( cd "$PROJECT_DIR" && bash Scripts/check-file-families.sh )
    ( cd "$PROJECT_DIR" && swift build --disable-sandbox --build-system native > /tmp/release-build.log 2>&1 ) || fail "swift build 失败，见 /tmp/release-build.log"
    ( cd "$PROJECT_DIR" && swift run --disable-sandbox --build-system native TestRunner > /tmp/release-test.log 2>&1 ) || fail "测试失败，见 /tmp/release-test.log"
    grep -q "所有测试通过" /tmp/release-test.log || fail "测试没打「所有测试通过」，见 /tmp/release-test.log"
else
    say "3/6 跳过门禁与测试（--dry-run）"
fi

if [ "$SKIP_CI" = "0" ] && command -v ghops > /dev/null && [ "$DRY_RUN" = "0" ]; then
    say "4/6 CI 闸门：确认远端 HEAD 的 CI 已绿"
    head_sha=$(git rev-parse HEAD)
    remote_sha=$(git ls-remote --heads "$REMOTE" "refs/heads/$BRANCH" | awk "{print \$1}")
    if [ "$head_sha" != "$remote_sha" ]; then
        fail "本地 HEAD 还没推到远端（本地 $head_sha / 远端 $remote_sha）：先 push 并等 CI 绿"
    fi
    checks=$(ghops api GET "/repos/$REPO/commits/$head_sha/check-runs" 2>/dev/null || true)
    if printf "%s" "$checks" | grep -q "\"conclusion\": *\"failure\""; then
        fail "CI 红——1.24.x / 1.25.0 / 1.26.0 就是栽在这里，先修再发"
    fi
    if printf "%s" "$checks" | grep -q "\"status\": *\"in_progress\""; then
        fail "CI 还在跑，等它结束再来"
    fi
    say "   ✅ CI 无失败"
else
    say "4/6 跳过 CI 闸门"
fi

say "5/6 改版本号"
if [ "$DRY_RUN" = "0" ]; then
    python3 - "$PLIST_SOURCE" "$AGENTS_FILE" "$VERSION" "$new_build" << PYEOF
import re, sys
plist, agents, version, build = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
s = open(plist).read()
s = re.sub(r"(<key>CFBundleShortVersionString</key>\s*<string>)[^<]*(</string>)",
           lambda m: m.group(1) + version + m.group(2), s, count=1)
s = re.sub(r"(<key>CFBundleVersion</key>\s*<string>)[^<]*(</string>)",
           lambda m: m.group(1) + build + m.group(2), s, count=1)
open(plist, "w").write(s)
a = open(agents).read()
a = re.sub(r"(- \*\*版本:\*\* )[0-9.]+", lambda m: m.group(1) + version, a, count=1)
open(agents, "w").write(a)
print("   plist 与 AGENTS.md 已更新")
PYEOF
    git add "$PLIST_SOURCE" "$AGENTS_FILE"
    git commit -q -m "chore: 版本号升到 $VERSION（构建号 $new_build）"
    git push "$REMOTE" "$BRANCH"
    git tag "$TAG"
    git push "$REMOTE" "$TAG"
else
    say "   （--dry-run 不改文件、不提交、不打 tag）"
fi

if [ "$DRY_RUN" = "1" ]; then
    say "6/6 完成（dry-run，仓库未被改动）"
    exit 0
fi

say "6/6 等 Release workflow"
run_id=""
for _ in $(seq 1 15); do
    sleep 20
    run_id=$(ghops api GET "/repos/$REPO/actions/runs?per_page=15" 2>/dev/null | tr "," "\n" | grep -A2 "\"id\"" | head -1 | sed -n "s/.*: *\([0-9]*\).*/\1/p" || true)
    [ -n "$run_id" ] && break
done
[ -n "$run_id" ] || fail "没找到 Release run，去 https://github.com/$REPO/actions 看"

for _ in $(seq 1 40); do
    line=$(ghops actions list "$REPO" --limit 5 2>/dev/null | grep "Release.*\[$TAG\]" | head -1 || true)
    say "   $line"
    case "$line" in
        *completed/success*) say "✅ 发布完成：https://github.com/$REPO/releases/tag/$TAG"; say "   记得同步 docs/发版记录.md 台账"; exit 0 ;;
        *completed/failure*) fail "Release 失败，见 https://github.com/$REPO/actions/runs/$run_id" ;;
    esac
    sleep 20
done
fail "等超时，去 https://github.com/$REPO/actions 看"
