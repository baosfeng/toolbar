#!/bin/bash
# 剪贴板访问授权探针 —— 编译 + 打包成最小 .app + 运行
#
# 为什么要打包成 .app 而不是直接 swift Scripts/clipboard-permission-probe.swift：
#   TCC（授权）是按「有 Bundle ID 的应用」记账的。裸脚本执行时进程没有稳定的
#   身份，系统弹窗的归属会漂移；打包 + adhoc 签名后，授权归属固定为
#   com.bsfeng.macmonitor.clipboardprobe，弹窗次数才可复现、可对照。
#
# 用法：
#   ./Scripts/clipboard-probe.sh                      # 默认观察 120 秒
#   ./Scripts/clipboard-probe.sh --seconds 60        # 观察 60 秒
#   ./Scripts/clipboard-probe.sh --force --seconds 30  # 每轮强制真实读取
#   DRY_RUN=1 ./Scripts/clipboard-probe.sh           # 只编译+打包+签名，不启动探针
#
# 参数（原样透传给探针）：
#   --seconds N   观察时长（秒），默认 120
#   --interval S  轮询间隔（秒），默认 0.5
#   --force       忽略 changeCount 判断，每轮都真实读取

set -euo pipefail

cd "$(dirname "$0")/.."

PROBE_SRC="Scripts/clipboard-permission-probe.swift"
APP_DIR="/tmp/ClipboardProbe.app"
EXEC_NAME="ClipboardProbe"
BUNDLE_ID="com.bsfeng.macmonitor.clipboardprobe"
LOG_PATH="/tmp/clipboard-probe.log"
DRY_RUN="${DRY_RUN:-0}"

# ─────────────────────────────────────────────────────────────
echo "════════════════════════════════════════════════════════════"
echo "  剪贴板访问授权探针 — 你现在该做什么"
echo "════════════════════════════════════════════════════════════"
echo "  ① 运行本脚本（默认观察 120 秒，可加 --seconds 60 缩短）："
echo "       cd $(pwd) && ./Scripts/clipboard-probe.sh"
echo "  ② 探针跑起来后，保持它运行，切到别的 App 复制 3~5 段文字"
echo "       （每次间隔几秒），把剪贴板内容变更多次。"
echo "  ③ 盯住屏幕：是否出现系统授权弹窗、弹了几次、弹窗写的是什么。"
echo "       结束后看日志：tail -n 30 ${LOG_PATH}"
echo ""
echo "  只看包结构不启动探针（安全）：DRY_RUN=1 ./Scripts/clipboard-probe.sh"
echo "════════════════════════════════════════════════════════════"
echo ""

echo "🔨 [1/4] 编译探针 → ${APP_DIR}/Contents/MacOS/${EXEC_NAME}"
if [ ! -f "${PROBE_SRC}" ]; then
    echo "❌ 找不到源码：${PROBE_SRC}（请在 NetworkMonitor 项目根目录下执行）" >&2
    exit 1
fi

rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

swiftc -O -o "${APP_DIR}/Contents/MacOS/${EXEC_NAME}" "${PROBE_SRC}"
echo "   ✅ 编译完成"

echo "📦 [2/4] 写入 Info.plist"
cat > "${APP_DIR}/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.bsfeng.macmonitor.clipboardprobe</string>
    <key>CFBundleExecutable</key>
    <string>ClipboardProbe</string>
    <key>CFBundleName</key>
    <string>ClipboardProbe</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
</dict>
</plist>
PLIST
plutil -lint "${APP_DIR}/Contents/Info.plist" > /dev/null
echo "   ✅ Info.plist 合法：${BUNDLE_ID}"

echo "🔏 [3/4] adhoc 签名（固定授权归属）"
codesign --force --sign - "${APP_DIR}"
codesign -dv "${APP_DIR}" 2>&1 | grep -E "Identifier|Signature|Info.plist" || true
echo "   ✅ 打包完成：${APP_DIR}"

if [ "${DRY_RUN}" = "1" ]; then
    echo ""
    echo "🧪 DRY_RUN=1：已构建并签名，跳过启动（不会读取剪贴板、不会弹授权窗）。"
    echo "   校验：codesign -dv ${APP_DIR} && plutil -lint ${APP_DIR}/Contents/Info.plist"
    exit 0
fi

echo "🚀 [4/4] 启动探针（stdout 直通下方，日志另存 ${LOG_PATH}）"
echo "────────────────────────────────────────────────────────────"
rm -f "${LOG_PATH}"
"${APP_DIR}/Contents/MacOS/${EXEC_NAME}" "$@"
STATUS=$?
echo "────────────────────────────────────────────────────────────"
echo "探针已退出，exit ${STATUS}"
if [ -f "${LOG_PATH}" ]; then
    echo "📄 日志：${LOG_PATH}"
    echo "   最后 5 行："
    tail -n 5 "${LOG_PATH}" | sed 's/^/   /'
fi
exit ${STATUS}
