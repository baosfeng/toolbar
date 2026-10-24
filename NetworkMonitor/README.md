# NetworkMonitor（SwiftPM 包）

macOS 菜单栏应用的源码包。构建、安装、测试与隐私说明统一在根目录 [README](../README.md)。

## 目标

| Target | 说明 |
|---|---|
| `NetworkMonitorCore` | 库：领域协议、数据库、统计、计费、传输协议（不依赖 AppKit） |
| `NetworkMonitor` | 可执行：菜单栏 UI、面板、Hook 监听、剪贴板与互传 |
| `TestRunner` | 可执行：手写断言测试 |

## 常用命令

```bash
swift build --disable-sandbox                 # 编译
swift run --disable-sandbox TestRunner        # 测试
./Scripts/build-app.sh release                # 打包并部署到 /Applications
bash Scripts/check-file-size.sh               # 大文件门禁
```

> 只装 Command Line Tools 时，给 `swift build` / `swift run` 追加 `--build-system native`。
