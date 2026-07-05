#!/bin/bash
# 一键构建 + 打包 NetworkMonitor.app（含 macMonitor 本机监控功能）
# Usage: ./Scripts/build-app.sh [debug|release]

set -e

cd "$(dirname "$0")/.."
BUILD_MODE="${1:-debug}"

APP_NAME="NetworkMonitor"
APP_DIR="dist/${APP_NAME}.app"

echo "🔨 正在构建 ${APP_NAME}（${BUILD_MODE}）..."

# 1. 使用 Swift PM 构建
if [ "$BUILD_MODE" = "release" ]; then
    swift build -c release --target ${APP_NAME} --disable-sandbox
    BINARY_PATH=".build/arm64-apple-macosx/release/${APP_NAME}"
else
    swift build --target ${APP_NAME} --disable-sandbox
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
    <string>1.0.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSInputMonitoringUsageDescription</key>
    <string>NetworkMonitor 需要输入监控权限来统计键盘敲击次数，不会记录按键内容。</string>
</dict>
</plist>
PLIST

# 6. 部署到 /Applications
echo ""
echo "📦 正在部署到 /Applications..."

# 杀掉正在运行的应用
RUNNING_PID=$(pgrep -f "${APP_NAME}" || true)
if [ -n "$RUNNING_PID" ]; then
    echo "   🛑 正在关闭正在运行的 ${APP_NAME}（PID: $RUNNING_PID）..."
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
