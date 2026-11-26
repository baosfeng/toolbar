#!/bin/bash
# release.sh —— 一站式发版：校验 → bump → 提交 → 推 → 打 tag → 跟到底
#
# 为什么要它：以前发版靠人记着「改两处版本号 + 打 tag + 看 CI」，连续踩了两次
# 「本机能编、CI 编不过」（any P! / effectIsInteractive），1.24.x / 1.25.0 / 1.26.0
# 全都因此没能发布。把人记的事交给脚本，并在动手前先过 CI 闸门。
#
# 用法：
#   Scripts/release.sh 1.30.0                # 真发版
#   Scripts/release.sh 1.30.0 --dry-run      # 只做检查，不改任何文件
#   Scripts/release.sh 1.30.0 --skip-ci-gate # 跳过 CI 闸门（不推荐）
#
# 发版产物（由 .github/workflows/release.yml 产出，共五个资产）：
#   Yilan-<版本>.dmg          —— universal（arm64 + x86_64），挂载后是「一览.app」
#   Yilan-<版本>-arm64.dmg    —— 只含 arm64
#   Yilan-<版本>-x86_64.dmg   —— 只含 x86_64
#   SHA256SUMS.txt            —— 三个 dmg 的校验和
#   update.json               —— 自动更新器的静态更新通道
# 版本号只在 NetworkMonitor/version.env 改（本脚本自动改），不要再手改别处。

set -euo pipefail

REPO="baosfeng/toolbar"
REMOTE="github"
BRANCH="main"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PROJECT_DIR/.." && pwd)"
# 版本号唯一真源：NetworkMonitor/version.env（build-app.sh 也从这里读）
VERSION_FILE="$PROJECT_DIR/version.env"
# 文档台账里的版本号是派生值，与 version.env 一起改（漏改只会让文档过时，不影响产物）
AGENTS_FILE="$REPO_ROOT/AGENTS.md"

VERSION=""
DRY_RUN=0
SKIP_CI=0

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --skip-ci-gate) SKIP_CI=1; shift ;;
        # 帮助正文的行号范围要覆盖到「发版产物」那几行：范围写死时每加一条资产说明就会被截断
        -h|--help) sed -n "2,19p" "$0"; exit 0 ;;
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
[ -f "$VERSION_FILE" ] || fail "缺少 NetworkMonitor/version.env（版本号唯一真源）"
old_version=$(sed -n "s/^VERSION=//p" "$VERSION_FILE" | head -1)
old_build=$(sed -n "s/^BUILD=//p" "$VERSION_FILE" | head -1)
case "$old_build" in ""|*[!0-9]*) fail "version.env 的 BUILD 必须是整数，读到：${old_build:-空}" ;; esac
new_build=$((old_build + 1))
say "   当前 ${old_version}（构建号 ${old_build}）→ 目标 ${VERSION}（构建号 ${new_build}）"
[ "$old_version" = "$VERSION" ] && fail "版本号已经是 ${VERSION}"

# 语义化比较：逐段按数值比（字符串比会把 1.9 判成大于 1.10）
IFS=. read -r oldMajor oldMinor oldPatch <<< "$old_version"
IFS=. read -r newMajor newMinor newPatch <<< "$VERSION"
higher=0
if [ "$newMajor" -gt "$oldMajor" ]; then higher=1
elif [ "$newMajor" -eq "$oldMajor" ]; then
    if [ "$newMinor" -gt "$oldMinor" ]; then higher=1
    elif [ "$newMinor" -eq "$oldMinor" ] && [ "$newPatch" -gt "$oldPatch" ]; then higher=1
    fi
fi
[ "$higher" = "1" ] || fail "新版本号必须大于当前 $old_version"
git rev-parse -q --verify "refs/tags/$TAG" > /dev/null && fail "本地已有 tag $TAG"
git ls-remote --tags "$REMOTE" "refs/tags/$TAG" 2>/dev/null | grep -q . && fail "远端已有 tag $TAG"

if [ "$DRY_RUN" = "0" ]; then
    say "3/6 门禁与测试"
    ( cd "$PROJECT_DIR" && bash Scripts/check-file-size.sh )
    ( cd "$PROJECT_DIR" && bash Scripts/check-file-families.sh )
    ( cd "$PROJECT_DIR" && bash Scripts/test-release-notes.sh ) || fail "发布说明生成器回归失败（链接 / hash / @提及）"
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
        fail "本地 HEAD 还没推到远端（本地 ${head_sha} / 远端 ${remote_sha}）：先 push 并等 CI 绿"
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
    python3 - "$VERSION_FILE" "$AGENTS_FILE" "$VERSION" "$new_build" << PYEOF
import re, sys
ver_file, agents, version, build = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
s = open(ver_file).read()
s = re.sub(r"(?m)^VERSION=.*$", "VERSION=" + version, s)
s = re.sub(r"(?m)^BUILD=.*$", "BUILD=" + build, s)
open(ver_file, "w").write(s)
a = open(agents).read()
a = re.sub(r"(- \*\*版本:\*\* )[0-9.]+", lambda m: m.group(1) + version, a, count=1)
open(agents, "w").write(a)
print("   version.env 与 AGENTS.md 已更新")
PYEOF
    git add "$VERSION_FILE" "$AGENTS_FILE"
    # 变量紧跟全角标点必须写 ${var}：多字节首字节会被当成变量名一部分，
    # macOS 自带 bash 下静默、CI / set -u 环境直接 unbound（本条实测踩过一次，发版中断在提交前）
    git commit -q -m "chore: 版本号升到 ${VERSION}（构建号 ${new_build}）"
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
        *completed/success*)
            say "   校验发布资产…"
            assets=$(ghops api GET "/repos/$REPO/releases/tags/$TAG" 2>/dev/null | tr "," "\n" | grep '"name"' || true)
            # 三个 dmg 一个都不能少：少一个单架构包，更新清单的 platforms 表就发不出去（生成器会 fail），
            # 少 universal 则手动下载的人在「不知道自己的芯片该选哪个」时没有默认选项
            for need in "Yilan-${VERSION}.dmg" "Yilan-${VERSION}-arm64.dmg" \
                        "Yilan-${VERSION}-x86_64.dmg" "SHA256SUMS.txt" "update.json"; do
                printf "%s" "$assets" | grep -q "\"${need}\"" || fail "发布里缺少资产 ${need}（发版没走完，别当成功）"
            done
            say "   ✅ 资产齐全：Yilan-${VERSION}.dmg / Yilan-${VERSION}-arm64.dmg / Yilan-${VERSION}-x86_64.dmg / SHA256SUMS.txt / update.json"
            say "✅ 发布完成：https://github.com/$REPO/releases/tag/$TAG"
            say "   记得同步 docs/发版记录.md 台账"
            exit 0 ;;
        *completed/failure*) fail "Release 失败，见 https://github.com/$REPO/actions/runs/$run_id" ;;
    esac
    sleep 20
done
fail "等超时，去 https://github.com/$REPO/actions 看"
