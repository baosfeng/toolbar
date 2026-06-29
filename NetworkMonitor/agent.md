# Agent Instructions

## 工作流程

每次完成功能修改后，按以下顺序执行：

### 第 1 步：运行测试

```bash
cd <repo>/NetworkMonitor && swift run --disable-sandbox TestRunner
```

所有测试通过（显示 `🎉 所有测试通过！`）后才能继续。有失败则先修复代码。

### 第 2 步：编译验证

```bash
cd <repo>/NetworkMonitor && swift build --disable-sandbox
```

确保无 error。

### 第 3 步：打包为 .app

```bash
cd <repo>/NetworkMonitor

APP_PATH="./dist/NetworkMonitor.app"
rm -rf "${APP_PATH}"
mkdir -p "${APP_PATH}/Contents/MacOS"

cat > "${APP_PATH}/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>NetworkMonitor</string>
    <key>CFBundleIdentifier</key>
    <string>com.example.NetworkMonitor</string>
    <key>CFBundleName</key>
    <string>NetworkMonitor</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

cp .build/debug/NetworkMonitor "${APP_PATH}/Contents/MacOS/NetworkMonitor"
```

不要生成 .dmg 文件。

## 提交规范

提交信息使用中文，格式：`<type>: <描述>`

- `feat:` — 新功能
- `refactor:` — 重构
- `fix:` — 修复 bug
- `chore:` — 杂项
