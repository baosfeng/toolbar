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
if [ "$BUILD_MODE" = "release" ]; then
    swift build -c release --disable-sandbox --build-system native
    BINARY_PATH=".build/arm64-apple-macosx/release/${APP_NAME}"
else
    swift build --disable-sandbox --build-system native
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
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.3.0</string>
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

# 6. 部署到 /Applications
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

# 显式 ad-hoc 签名并固定标识符（com.example.NetworkMonitor）。
# 不指定 --identifier 时系统会生成「NetworkMonitor-<hash>」临时标识，每次构建都变，
# 导致 macOS 把 App 当成新应用，本地网络权限每次重新部署都失效（表现为 UDP errno 65）。
echo "   🔏 签名（固定标识符 + 固定证书）..."
# 优先用本机自签名证书：签名身份 = 证书 + identifier，不随代码变化，
# macOS 的本地网络授权才能「记住」，不会每次重新部署都弹窗。
# 证书不存在时回落 ad-hoc（身份随 cdhash 变化，权限需重新授权）。
SIGN_IDENTITY="NetworkMonitor Local Signing"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "${SIGN_IDENTITY}"; then
    codesign --force --deep --sign "${SIGN_IDENTITY}" --identifier com.example.NetworkMonitor "${INSTALL_PATH}" 2>&1 | tail -2 || true
    echo "      使用证书：${SIGN_IDENTITY}"
else
    codesign --force --deep --sign - --identifier com.example.NetworkMonitor "${INSTALL_PATH}" 2>&1 | tail -2 || true
    echo "      未找到证书，回落 ad-hoc（每次构建权限会重新询问）"
fi

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
