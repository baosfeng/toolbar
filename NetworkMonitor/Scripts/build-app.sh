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

echo ""
echo "🎉 交付物就绪！"
echo "   📦 应用位置：${APP_DIR}"
echo ""
echo "📋 应用大小："
ls -lh "$APP_DIR/Contents/MacOS/${APP_NAME}"
echo ""
echo "🚀 三步上手："
echo "   1. 打开 Finder → 前往 → 前往文件夹"
echo "      输入: $(cd "$APP_DIR" && pwd)"
echo "   2. 双击 NetworkMonitor.app"
echo "   3. 菜单栏出现 📊 图标，开始监控"
echo ""
echo "   💡 新增本机监控：应用追踪、击键统计、系统采样等"
