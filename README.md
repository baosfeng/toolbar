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
| 网络速度 | 菜单栏实时显示上下行速度；今日流量与近 6 日汇总（getifaddrs 差分 + TrafficTracker） |
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

### 方式一：下载 Release（推荐）

1. 打开 [Releases](https://github.com/baosfeng/toolbar/releases)，下载最新的 `NetworkMonitor.app.zip`
2. 解压，把 `NetworkMonitor.app` 拖进「应用程序」
3. 首次启动：**右键点图标 → 打开**（应用未经过 Apple 公证，直接双击会被 Gatekeeper 拦下）
4. 如果右键打开仍被拦：系统设置 → 隐私与安全性 → 页面底部点「仍要打开」
5. 启动成功后**没有 Dock 图标、没有主窗口**，菜单栏右侧会出现网速数字，这就是应用

> 想让它开机自启：点开面板右上角齿轮 → 勾选「开机自启动」，随后按系统提示在「登录项」里允许。

### 方式二：从源码构建

```bash
git clone https://github.com/baosfeng/toolbar.git
cd toolbar/NetworkMonitor
./Scripts/build-app.sh release
```

脚本会编译、打包、签名并部署到 `/Applications/NetworkMonitor.app`，然后自动启动。

## 使用

### 打开面板

左键单击菜单栏的网速数字，弹出面板；面板有三个标签页：

| 标签页 | 内容 |
|---|---|
| **网络** | 今日下行/上行、近 6 日下行趋势、活跃进程流量 Top 10 |
| **剪贴板** | 历史卡片流、搜索框、类型过滤、Paste Stack |
| **传送** | 附近设备、发送文件、扫码接收、传输任务列表 |

### 剪贴板历史

- 全局快捷键 **⌘⌥V** 直接唤起剪贴板面板（可在剪贴板设置里改）
- 面板内操作：`↑↓` 选择、`⌘` 粘贴、`⌘1–9` 直选、`Esc` 收起；双击卡片也能直接粘贴
- 搜索框支持模糊搜索；`Tab` 切换类型过滤
- 剪贴板设置：面板内按 `⌘,`，可改快捷键、快速粘贴、采集模式、面板高度、历史上限、黑名单与权限状态

### 局域网互传

1. 两台设备连同一个 Wi-Fi
2. 需要手机传文件到 Mac：面板「传送」→「扫码接收」→ 用手机相机扫码，浏览器里直接选文件上传（二维码 10 分钟内有效）
3. Mac 主动发送：把文件拖进「传送」页的投放区，或选「附近设备」后点「发送」
4. 首次接收未配对设备时，输入对方显示的 4 位配对码即可；配对后可免确认直传
5. 支持断点续传；接收完成的任务可以从列表里直接拖出为真实文件

### 额度查询

1. 打开面板「额度」标签
2. 选择一个 provider（Ollama / Open Design）
3. 粘贴凭据后点「保存并查询」：
   - **Ollama**：在 [ollama.com/settings/keys](https://ollama.com/settings/keys) 创建 API Key
   - **Open Design**：登录网页后，从浏览器开发者工具里复制 `__Secure-better-auth.session_token` 的 Cookie 值
4. 凭据只保存在本机，请求直接发往 provider 官方接口
5. 额度低于 5%/4%/3%/2%/1% 时会弹系统通知提醒（需允许通知）

### 设置菜单

面板右上角齿轮菜单：

- **传送设置…**：端口、接收目录等互传参数
- **开机自启动**：勾选后走系统登录项（`SMAppService`）
- **退出 NetworkMonitor**：`⌘Q`

## 权限

| 权限 | 什么时候需要 | 不给会怎样 |
|---|---|---|
| 辅助功能 | Paste Stack 的 `⌘V` 监听与自动粘贴 | 普通复制能记录，但顺序粘贴/自动粘贴不生效 |
| 本地网络 | 局域网发现与文件互传 | 搜不到设备、扫码接收不可用 |
| 通知 | 额度阈值提醒、传输完成提醒 | 不弹通知，功能不受影响 |

剪贴板读取本身不需要额外授权（macOS 15 起首次访问会提示一次）。系统设置路径：隐私与安全性 → 辅助功能 / 本地网络 / 通知。

## 数据与卸载

- 数据位置：`~/Library/Application Support/macMonitor/monitor.db`（SQLite，含剪贴板历史与流量记录）
- 卸载：先退出应用，删除 `/Applications/NetworkMonitor.app`；如需清除数据，再删除上面的 `macMonitor` 目录

## 常见问题

**双击提示「无法验证开发者」？**
右键 → 打开；或系统设置 → 隐私与安全性 → 「仍要打开」。

**菜单栏看不到图标？**
确认应用已启动（活动监视器里找 NetworkMonitor）；若装了 Bartender 等菜单栏管理工具，检查是否被折叠。

**⌘⌥V 没反应？**
先在剪贴板设置里确认快捷键没被其他应用占用，再检查辅助功能权限是否已授权。

**传送搜不到设备？**
确认两台设备在同一 Wi-Fi、已允许「本地网络」权限；部分公共 Wi-Fi 会屏蔽设备互访。

## 测试

```bash
cd NetworkMonitor
swift run --disable-sandbox --build-system native TestRunner
```

> 只安装 Command Line Tools 的机器，默认构建后端会在会话初始化阶段失败，给 `swift build` / `swift run` 追加 `--build-system native` 即可；详见[踩坑记录](docs/踩坑/构建/swift-build-会话初始化失败.md)。

CI 在 GitHub 托管的 macOS runner 上执行同样的构建、测试与大文件门禁。

## 项目结构

```
NetworkMonitor/
  Package.swift
  Sources/
    NetworkMonitor/        # 可执行：菜单栏 UI、面板、剪贴板与互传
    NetworkMonitorCore/    # 库：协议、数据库、计费、传输协议（不依赖 AppKit）
    TestRunner/            # 可执行：手写断言测试
  Scripts/                 # 构建、打包、大文件门禁
docs/                      # 设计规格、调研、踩坑记录
.agents/skills/            # 项目编码规范 skill
```

## 隐私

- 网速、剪贴板、互传数据只写入本地 `~/Library/Application Support/macMonitor/monitor.db`
- 唯一的对外请求来自你配置的额度服务（Ollama / Open Design），凭据由你本机输入
- 无遥测、无自动更新、无后台上报

## 贡献

- 提交前请阅读[构建与测试](docs/开发指南/构建与测试.md)与[提交规范](docs/开发指南/提交规范.md)
- 编码规范见 [.agents/skills/toolbar-coding-standards](.agents/skills/toolbar-coding-standards/SKILL.md)
- 文档导航见 [docs/索引.md](docs/索引.md)

## 许可证

[MIT](LICENSE)
