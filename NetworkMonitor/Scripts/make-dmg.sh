#!/bin/bash
# 把一个 .app 打成只读压缩 dmg —— 发版与本地预览共用的唯一打 dmg 实现
#
# 为什么单独成一支：发版要打三种包（universal + arm64 + x86_64），各写一份 hdiutil
# 参数迟早漂移；而「包名带架构后缀」正是用户反复反馈的问题——暂存目录里必须先把包名
# 改回「一览.app」，用户拖进「应用程序」后看到的才是干净的名字。
#
# 用法：
#   Scripts/make-dmg.sh <app 路径> <输出 dmg 路径> [卷名后缀]
#   例：Scripts/make-dmg.sh dist/一览-arm64.app dist/Yilan-1.31.0-arm64.dmg arm64
#
# 产物：挂载后是「一览.app」+ 指向「应用程序」的快捷方式（只读压缩卷 UDZO / HFS+）

set -euo pipefail

# 入参可以是相对调用者目录的路径，而下面要 cd 到脚本自己所在的目录去读 version.env，
# 先把调用时的工作目录记下来，两个路径统一转成绝对路径再往下走
CALLER_PWD="$PWD"
cd "$(dirname "$0")/.."

# 包名与 build-app.sh 的 APP_BUNDLE_NAME 同源（Finder / 启动台里看到的名字就是它）
APP_BUNDLE_NAME="一览"

[ -f version.env ] || { echo "❌ 缺少 version.env（版本号唯一真源）" >&2; exit 1; }
# shellcheck source=version.env
. ./version.env

say() { echo "[dmg] $*"; }
fail() { echo "❌ $*" >&2; exit 1; }

abspath() {
    case "$1" in
        /*) printf '%s\n' "$1" ;;
        *) printf '%s\n' "${CALLER_PWD}/$1" ;;
    esac
}

if [ $# -lt 2 ]; then
    echo "用法：Scripts/make-dmg.sh <app 路径> <输出 dmg 路径> [卷名后缀]" >&2
    exit 2
fi

APP_PATH="$(abspath "$1")"
DMG_PATH="$(abspath "$2")"
VOLUME_SUFFIX="${3:-}"

[ -d "$APP_PATH" ] || fail "app 不存在：$APP_PATH"
case "$APP_PATH" in
    *.app) ;;
    *) fail "入参要是 .app 包：$APP_PATH" ;;
esac

# 卷名顺序与改造前的 universal dmg 完全一致（「一览 1.31.0」）：Finder 侧栏里这块牌子
# 是用户可见文案，把 dmg 抽成公共脚本不该顺带改它；带后缀只是为了某天同时挂着两个
# 单架构 dmg 时侧栏里不出现两个同名卷
VOLUME_NAME="${APP_BUNDLE_NAME} ${VERSION}"
[ -z "$VOLUME_SUFFIX" ] || VOLUME_NAME="${VOLUME_NAME} ${VOLUME_SUFFIX}"

STAGING="$(mktemp -d "${TMPDIR:-/tmp}/yilan-dmg.XXXXXX")"
# trap 而不是依赖正常路径清理：中途任何一步失败都不该在 /tmp 里留下几百 MB 的包
cleanup() { rm -rf "$STAGING"; }
trap cleanup EXIT

cp -R "$APP_PATH" "$STAGING/${APP_BUNDLE_NAME}.app"
ln -s /Applications "$STAGING/Applications"

mkdir -p "$(dirname "$DMG_PATH")"
rm -f "$DMG_PATH"
# UDZO = 只读压缩卷；HFS+ 兼容所有仍支持本应用的 macOS 版本
hdiutil create -volname "$VOLUME_NAME" -srcfolder "$STAGING" \
    -ov -format UDZO -fs HFS+ -quiet "$DMG_PATH" >/dev/null \
    || fail "hdiutil create 失败：$DMG_PATH"

# hdiutil 偶尔返回 0 却没有落盘（磁盘写满 / 目标被并发删掉），产物不存在一律算失败，
# 否则下游的 checksums 与更新清单会挂在一个不存在的资产上
[ -f "$DMG_PATH" ] || fail "dmg 没有生成：$DMG_PATH"
say "已生成 ${DMG_PATH}（$(du -h "$DMG_PATH" | cut -f1)，卷名 ${VOLUME_NAME}）"
