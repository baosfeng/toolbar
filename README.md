# NetworkMonitor

> macOS 菜单栏的网速与额度监控，外加剪贴板历史和局域网文件互传。

[![CI](https://github.com/baosfeng/toolbar/actions/workflows/ci.yml/badge.svg)](https://github.com/baosfeng/toolbar/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey.svg)](#系统要求)
[![Swift](https://img.shields.io/badge/Swift-6.3-orange.svg)](https://swift.org)
[![Release](https://img.shields.io/github/v/release/baosfeng/toolbar?display_name=tag&sort=semver)](https://github.com/baosfeng/toolbar/releases)
[![Downloads](https://img.shields.io/github/downloads/baosfeng/toolbar/total)](https://github.com/baosfeng/toolbar/releases)

![额度页](docs/设计/额度页-聚合视图-预览/展开态-浅色.png)

纯 Swift / SwiftPM 实现的菜单栏常驻应用：实时网速、进程流量、Ollama 与 Open Design 额度、剪贴板历史、局域网文件互传。所有数据落在本地 SQLite，没有遥测与后台上报。

## 功能

| 模块 | 说明 |
|---|---|
| 网络速度 | 菜单栏实时显示上下行速度；今日流量与近 7 日汇总（getifaddrs 差分 + TrafficTracker） |
| 进程流量 | nettop 后台采样，进程级 Top 10 |
| 额度查询 | Ollama（余额 + 用量）、Open Design（credits 窗口 + 工作区用量）；`BillingProvider` 协议 + 注册表，新增 provider 只需实现协议并注册 |
| 剪贴板历史 | 全局快捷键唤起面板、模糊搜索、Paste Stack 顺序粘贴、图片原图落盘 |
| 局域网互传 | UDP 发现 + HTTP 传输 + 扫码接收 + PIN 配对，支持断点续传 |

## 界面

| 额度页聚合视图 | 局域网传送面板 |
|---|---|
| ![额度页](docs/设计/额度页-聚合视图-预览/展开态-浅色.png) | ![传送面板](docs/设计/局域网文件互传-原型/预览-mac.png) |

> 截图为可交互原型（`docs/设计/*-原型/原型.html`）的渲染结果，与当前实现一致。

## 系统要求

- macOS 14 (Sonoma) 或更高
- Apple Silicon（ARM64）
- 构建需要 Swift 6.3 工具链（Swift 6 严格并发）

## 安装

### 下载 Release

到 [Releases](https://github.com/baosfeng/toolbar/releases) 下载 `NetworkMonitor.app.zip`，解压后拖入「应用程序」。首次启动若提示「无法验证开发者」，右键 → 打开即可（ad-hoc 签名）。

### 从源码构建

```bash
git clone https://github.com/baosfeng/toolbar.git
cd toolbar/NetworkMonitor
./Scripts/build-app.sh release
```

脚本会完成编译、打包并部署到 `/Applications/NetworkMonitor.app`。

## 测试

```bash
cd NetworkMonitor
swift run --disable-sandbox TestRunner
```

> 只安装 Command Line Tools 的机器，默认构建后端会在会话初始化阶段失败，给 `swift build` / `swift run` 追加 `--build-system native` 即可；详见[踩坑记录](docs/踩坑/构建/swift-build-会话初始化失败.md)。

CI 在 GitHub 托管的 macOS runner 上执行同样的构建、测试与大文件门禁。

## 项目结构

```
NetworkMonitor/
  Package.swift
  Sources/
    NetworkMonitor/        # 可执行：菜单栏 UI、面板、Hook 监听、互传与剪贴板
    NetworkMonitorCore/    # 库：协议、数据库、统计、计费、传输协议（不依赖 AppKit）
    TestRunner/            # 可执行：手写断言测试
  Scripts/                 # 构建、打包、大文件门禁
docs/                      # 设计规格、调研、踩坑记录
.agents/skills/            # 项目编码规范 skill
```

## 隐私

- 网络、Token、剪贴板、互传数据只写入本地 `~/Library/Application Support/macMonitor/monitor.db`
- 唯一的对外请求来自你配置的额度服务（Ollama / Open Design），凭据由你本机输入
- 无遥测、无自动更新、无后台上报

## 贡献

- 提交前请阅读[构建与测试](docs/开发指南/构建与测试.md)与[提交规范](docs/开发指南/提交规范.md)
- 编码规范见 [.agents/skills/toolbar-coding-standards](.agents/skills/toolbar-coding-standards/SKILL.md)
- 文档导航见 [docs/索引.md](docs/索引.md)

## 许可证

[MIT](LICENSE)
