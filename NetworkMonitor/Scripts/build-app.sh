#!/bin/bash
# Build and package NetworkMonitor.app
# Usage: ./Scripts/build-app.sh [debug|release]

set -e

cd "$(dirname "$0")/.."
BUILD_MODE="${1:-debug}"

echo "🔨 Building NetworkMonitor ($BUILD_MODE)..."

# Clean dist
rm -rf dist/NetworkMonitor.app
mkdir -p dist/NetworkMonitor.app/Contents/MacOS
mkdir -p dist/NetworkMonitor.app/Contents/Resources
mkdir -p dist/NetworkMonitor.app/Contents/Frameworks
mkdir -p .build/obj

# Compile Core module
echo "📦 Compiling NetworkMonitorCore..."
swiftc \
  -target arm64-apple-macosx14.0 \
  -emit-module \
  -module-name NetworkMonitorCore \
  -o .build/obj/NetworkMonitorCore.swiftmodule \
  -emit-library -o .build/obj/libNetworkMonitorCore.dylib \
  Sources/NetworkMonitorCore/Core.swift \
  -framework Foundation

# Compile main app
echo "📦 Compiling NetworkMonitor..."
swiftc \
  -target arm64-apple-macosx14.0 \
  -parse-as-library \
  -I .build/obj \
  -L .build/obj \
  -lNetworkMonitorCore \
  -o dist/NetworkMonitor.app/Contents/MacOS/NetworkMonitor \
  Sources/NetworkMonitor/main.swift \
  Sources/NetworkMonitor/NetworkMonitor.swift \
  -framework AppKit \
  -framework Foundation \
  -framework ServiceManagement \
  -framework CoreWLAN \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks

# Copy dylib
cp .build/obj/libNetworkMonitorCore.dylib dist/NetworkMonitor.app/Contents/Frameworks/

# Generate icon if not exists
if [ ! -f dist/NetworkMonitor.app/Contents/Resources/AppIcon.icns ]; then
    echo "🎨 Generating app icon..."
    swift Scripts/generate-icon.swift dist/NetworkMonitor.app/Contents/Resources 2>/dev/null || true
    # Fallback: copy from scripts if generated there
    if [ -f Scripts/AppIcon.icns ]; then
        cp Scripts/AppIcon.icns dist/NetworkMonitor.app/Contents/Resources/
    fi
fi

# Write Info.plist
cat > dist/NetworkMonitor.app/Contents/Info.plist << 'PLIST'
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
    <string>1.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

echo ""
echo "✅ Build complete!"
echo "   App: dist/NetworkMonitor.app"
ls -lh dist/NetworkMonitor.app/Contents/MacOS/NetworkMonitor
