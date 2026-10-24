# Agent Instructions

## 工作流程

每次完成功能修改后，在仓库根目录按以下顺序执行：

### 第 1 步：运行测试

```bash
cd NetworkMonitor && swift run --disable-sandbox TestRunner
```

所有测试通过（显示 `🎉 所有测试通过！`）后才能继续。有失败则先修复代码。

### 第 2 步：编译验证

```bash
cd NetworkMonitor && swift build --disable-sandbox
```

确保无 error。

### 第 3 步：打包为 .app

```bash
cd NetworkMonitor

APP_PATH="./dist/NetworkMonitor.app"

# 首次创建 .app 目录结构，后续只替换可执行文件（保持 inode 不变）
if [ ! -d "${APP_PATH}" ]; then
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
    <string>网络监控</string>
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
fi

# 只替换可执行文件，不删 .app 目录
cp .build/debug/NetworkMonitor "${APP_PATH}/Contents/MacOS/NetworkMonitor"
```

不要生成 .dmg 文件。**不要用 codesign 签名**，签名会导致 app 无法打开。

## 提交规范

提交信息使用中文，格式：`<type>: <描述>`

- `feat:` — 新功能
- `refactor:` — 重构
- `fix:` — 修复 bug
- `chore:` — 杂项
