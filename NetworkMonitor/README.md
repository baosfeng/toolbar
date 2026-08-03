# NetworkMonitor — macOS 菜单栏监控

一个运行在 macOS 菜单栏的轻量监控应用：实时显示网络上下行速度与每日流量，并通过 UDS 接收 Reasonix AI 助手事件，统计 Token 用量、花费与 AI 分析数据。

## 功能

- 🌐 **网速监控** — 菜单栏实时显示下载/上传速度（↑下行 绿 / ↓上行 橙）
- 📊 **每日流量** — 菜单栏标题显示今日流量，二级菜单汇总近 7 日流量
- 🖥️ **活跃进程** — 进程级流量 Top 10（nettop 后台采样，3 秒间隔）
- 🧠 **Token 监控** — 今日 Token 总数与花费（CNY），24 小时柱状图，近 7 日历史
- 🤖 **AI 分析** — 实时工具动态、工具统计（成功率/耗时）、模型排行、项目排行、会话概览
- 🔔 **轮次通知** — AI 轮次完成/失败时弹系统通知，点击跳转会话文件
- 🚫 隐藏 Dock 图标，作为菜单栏附属应用运行

## 技术栈

| 项目 | 内容 |
|------|------|
| 语言 | Swift 6.3（Swift 6 严格并发） |
| 最低系统 | macOS 14 (Sonoma) |
| 芯片 | Apple Silicon (ARM64) |
| UI | AppKit（NSStatusItem / NSMenu） |
| 图表 | DGCharts（Swift PM 依赖） |
| 数据库 | SQLite3（本地，WAL 模式） |
| 通信 | Unix Domain Socket（Datagram） |

## 构建

```bash
cd NetworkMonitor

# 仅编译
swift build --disable-sandbox

# 打包为 .app 并部署到 /Applications（自动启动）
./Scripts/build-app.sh          # debug 模式
./Scripts/build-app.sh release  # release 模式
```

> 交付物为 `dist/NetworkMonitor.app`，**不生成 .dmg**。

## 测试

```bash
cd NetworkMonitor
swift run --disable-sandbox TestRunner
```

测试覆盖：格式化工具、nettop 解析、hook JSON 解析、数据库（写入/upsert/工具调用/货币迁移/过期清理）、TokenUsageProvider 全接口。

## 数据与隐私

- 数据仅存本地：`~/Library/Application Support/macMonitor/monitor.db`
- 金额以 CNY 存储（汇率默认 7.2，可用 UserDefaults 键 `usdToCnyRate` 覆盖）
- 统计按本地时区聚合（SQLite 表达式索引随时区重建）
- 过期数据自动清理（明细 90 天 / 会话 180 天）
- 无任何网络上传功能

## 权限

- 开机自启动通过 `SMAppService.mainApp.register()` 实现（需登录时授权）
- 首次启动若提示"无法验证开发者"：右键 → 打开（ad-hoc 签名）

## 卸载

删除 `/Applications/NetworkMonitor.app` 即可；如需清除数据，删除 `~/Library/Application Support/macMonitor/`。
