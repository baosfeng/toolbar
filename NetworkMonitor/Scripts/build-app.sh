#!/bin/bash
# 一键构建 + 打包 NetworkMonitor.app（含 macMonitor 本机监控功能）
# Usage: ./Scripts/build-app.sh [debug|release]
#
# 注意：下面两条构建命令都追加了 --build-system 参数（取值 native）。本机只装了 Command Line Tools
# （无 Xcode.app），默认的 swiftbuild/XCBuild 后端在 session 初始化阶段就会失败
# （SessionFailedError: Unknown error parsing property list），该参数用于绕开此故障。
# native 引擎已被官方标记 deprecated，构建时会多一条 deprecation 警告；装好 Xcode 后
# （sudo xcode-select -s /Applications/Xcode.app/Contents/Developer）即可删掉这两个参数。

set -e

cd "$(dirname "$0")/.."
BUILD_MODE="${1:-debug}"

APP_NAME="NetworkMonitor"
APP_DIR="dist/${APP_NAME}.app"

echo "🔨 正在构建 ${APP_NAME}（${BUILD_MODE}）..."

# 1. 使用 Swift PM 构建（完整构建，保证链接出可执行文件；--target 在 SwiftPM 6.3 下不产出二进制）
# 构建后端：默认 native（本机仅有 Command Line Tools 时的绕行方案）；
# 完整 Xcode 环境（含 CI）可传 BUILD_SYSTEM=default 使用系统默认后端。
BUILD_SYSTEM_ARG="--build-system native"
if [ "${BUILD_SYSTEM:-native}" != "native" ]; then
    BUILD_SYSTEM_ARG=""
fi

if [ "$BUILD_MODE" = "release" ]; then
    # shellcheck disable=SC2086  # 允许为空，从而不追加任何构建后端参数
    swift build -c release --disable-sandbox $BUILD_SYSTEM_ARG
    BINARY_PATH=".build/arm64-apple-macosx/release/${APP_NAME}"
else
    # shellcheck disable=SC2086
    swift build --disable-sandbox $BUILD_SYSTEM_ARG
    BINARY_PATH=".build/arm64-apple-macosx/debug/${APP_NAME}"
fi

# 2. 创建 .app 包结构
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# 3. 复制可执行文件
cp "$BINARY_PATH" "$APP_DIR/Contents/MacOS/${APP_NAME}"

# 4. 复制图标
if [ -f "Scripts/AppIcon.icns" ]; then
    cp "Scripts/AppIcon.icns" "$APP_DIR/Contents/Resources/"
fi

# 5. 写入 Info.plist
cat > "$APP_DIR/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>NetworkMonitor</string>
    <key>CFBundleIdentifier</key>
    <string>com.example.NetworkMonitor</string>
    <key>CFBundleName</key>
    <string>NetworkMonitor</string>
    <key>CFBundleVersion</key>
    <string>3</string>
    <key>CFBundleShortVersionString</key>
    <string>1.5.1</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSInputMonitoringUsageDescription</key>
    <string>NetworkMonitor 需要输入监控权限来统计键盘敲击次数，不会记录按键内容。</string>
    <key>NSLocalNetworkUsageDescription</key>
    <string>NetworkMonitor 需要访问本地网络来发现同一 Wi-Fi 下的设备并互传文件，不会上传到任何服务器。</string>
</dict>
</plist>
PLIST

# 6. 签名
# 证书名可通过 SIGN_IDENTITY 覆盖（CI 用 Secrets 传入同一张自签名证书）；
# 未找到证书时回落 ad-hoc（身份随 cdhash 变化，权限需重新授权）。
SIGN_IDENTITY="${SIGN_IDENTITY:-NetworkMonitor Local Signing}"
SIGN_ENTITLEMENTS="${SIGN_ENTITLEMENTS:-}"

# 校验签名是否落在稳定身份上：ad-hoc 签名的 designated requirement 是 cdhash，
# 每次构建都变，TCC 授权（屏幕录制 / 辅助功能 / 本地网络）会被当成另一个应用。
assert_stable_signature() {
    local target="$1"
    local requirement
    requirement=$(codesign -d -r- "$target" 2>&1 || true)
    if printf '%s' "$requirement" | grep -q "cdhash"; then
        echo "      ❌ 签名是 ad-hoc（designated requirement 依赖 cdhash），重建后权限会失效" >&2
        return 1
    fi
    echo "      签名要求：$(printf '%s' "$requirement" | tail -1 | sed "s/^designated => //")"
}

sign_app() {
    local target="$1"
    local args=(--force --deep --identifier com.example.NetworkMonitor)
    local output
    if [ -n "${SIGN_ENTITLEMENTS}" ] && [ -f "${SIGN_ENTITLEMENTS}" ]; then
        args+=(--entitlements "${SIGN_ENTITLEMENTS}")
    fi
    if security find-identity -v -p codesigning 2>/dev/null | grep -q "${SIGN_IDENTITY}"; then
        if ! output=$(codesign "${args[@]}" --sign "${SIGN_IDENTITY}" "$target" 2>&1); then
            echo "      ❌ 证书签名失败：${output}" >&2
            echo "      可用身份：$(security find-identity -v -p codesigning 2>/dev/null | tail -5)" >&2
            return 1
        fi
        if [ -n "$output" ]; then printf '%s\n' "$output" | tail -2; fi
        echo "      使用证书：${SIGN_IDENTITY}"
        assert_stable_signature "$target"
    else
        if ! output=$(codesign "${args[@]}" --sign - "$target" 2>&1); then
            echo "      ❌ ad-hoc 签名失败：${output}" >&2
            return 1
        fi
        echo "      ⚠️  未找到证书 ${SIGN_IDENTITY}，回落 ad-hoc（每次构建权限会重新询问）"
    fi
}
# 7. 部署到 /Applications
if [ "${SKIP_INSTALL:-0}" = "1" ]; then
    echo ""
    echo "🔏 签署 ${APP_DIR} ..."
    sign_app "$APP_DIR"
    echo "📦 已生成 ${APP_DIR}（SKIP_INSTALL=1，跳过部署到 /Applications）"
    exit 0
fi

echo ""
echo "📦 正在部署到 /Applications..."

# 杀掉正在运行的应用
RUNNING_PID=$(pgrep -f "${APP_NAME}" || true)
if [ -n "$RUNNING_PID" ]; then
    echo "   🛑 正在关闭正在运行的 ${APP_NAME}（PID: ${RUNNING_PID}）..."
    kill "$RUNNING_PID" 2>/dev/null || true
    sleep 1
    # 确保进程已退出
    if kill -0 "$RUNNING_PID" 2>/dev/null; then
        echo "   ⚠️  进程未退出，强制终止..."
        kill -9 "$RUNNING_PID" 2>/dev/null || true
        sleep 0.5
    fi
fi

# 删除旧的 /Applications 版本
INSTALL_PATH="/Applications/${APP_NAME}.app"
if [ -d "$INSTALL_PATH" ]; then
    echo "   🗑️  删除旧版本 ${INSTALL_PATH}..."
    rm -rf "$INSTALL_PATH"
fi

# 复制到 /Applications
cp -R "$APP_DIR" "$INSTALL_PATH"
echo "   ✅ 已复制到 ${INSTALL_PATH}"

# 显式签名并固定标识符（com.example.NetworkMonitor）。
# 不指定 --identifier 时系统会生成「NetworkMonitor-<hash>」临时标识，每次构建都变，
# 导致 macOS 把 App 当成新应用，本地网络权限每次重新部署都失效（表现为 UDP errno 65）。
echo "   🔏 签名（固定标识符 + 固定证书）..."
sign_app "$INSTALL_PATH"

# 打开应用
echo "   🚀 正在启动 ${APP_NAME}..."
open "$INSTALL_PATH"

echo ""
echo "🎉 部署完成！"
echo "   📦 应用位置：${INSTALL_PATH}"
echo ""
echo "📋 应用大小："
ls -lh "${INSTALL_PATH}/Contents/MacOS/${APP_NAME}"
echo ""
echo "💡 应用已自动启动，查看菜单栏 📊 图标"
