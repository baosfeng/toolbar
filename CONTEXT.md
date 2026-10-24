# 项目上下文（共享语言）

NetworkMonitor / macMonitor — macOS 菜单栏应用。本文档定义项目术语，帮助 agent 用 1 个词代替 20 个词。术语更新时同步维护本文件。

## 核心术语

| 术语 | 定义 | 避免的说法 |
|------|------|-----------|
| **组合根** | `AppCoordinator`，唯一允许创建具体实现类的地方 | 依赖容器、工厂 |
| **仓储（Repository）** | 按领域拆分的数据库接口：`ClipboardRepository` | 数据访问层 |
| **AppDatabase** | `DatabaseService & ClipboardRepository` 组合 typealias，UI 注入用 | 数据库对象 |
| **分层刷新** | 菜单栏更新频率分层：网速 1s / 流量 5s | 定时器策略 |
| **计费 provider** | 实现 `BillingProvider` 协议的云服务商额度源（Ollama / Open Design），注册后自动出现在额度页 provider 选择器 | 计费插件、余额接口 |
| **编码计划窗口** | Open Design 按 credits 计量的滚动额度窗口（5 小时 / 每周），映射为 `BillingPercentLimit` | 套餐、配额 |
| **用量聚合** | Open Design `/billing/usage` 顶层 `summary` + `totalCount` 为全范围汇总（与分页 `limit` 无关） | 明细列表 |

## 关键事实（易错点）

- 数据库金额一律 **CNY**（USD 在写入前经 `CurrencyConfig` 转换）
- 剪贴板数据落库后发 `AppEvents.postClipboardChanged()`，UI 订阅后立即刷新
- `NetworkMonitorCore` 禁止 import AppKit；依赖方向 App → Core
- 测试：`swift run --disable-sandbox TestRunner`，内存 SQLite，无 XCTest
- Open Design 额度接口只认浏览器 Cookie（`__Secure-better-auth.session_token`），Bearer 一律 401；用量接口的 `entries` 分页上限 100 条但 30 天可达 1.6 万条，**汇总必须读顶层 `summary` / `totalCount`，不要翻页**
