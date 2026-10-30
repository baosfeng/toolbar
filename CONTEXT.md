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
| **Token 用量** | DSH 会话事件流中 `assistant/message` 的 `usage` 聚合（未缓存输入 / 输出 / 缓存读），按 Asia/Shanghai 分桶 | token 统计、消耗量 |
| **会话去重** | 同一会话目录的 v0/v3/v4 多版本文件按内容键（time + model + 四项计数）合并；`seq` 跨版本会重启，不可作键 | 去重、合并 |
| **系统指标快照** | `SystemMetricsSnapshot`（timestamp + cpu/gpu/memory/disk/thermal 全可选）：某项不可得就 nil，UI 显示「—」，不隐藏整卡 | 状态对象、监控数据 |
| **首帧基线** | 差分类指标（CPU 利用率、磁盘读写速率、GPU 利用率）首帧只建基线、返回 nil 而非 0，第二次起才有值 | 预热、初始化 |
| **P/E 核顺序** | 每核利用率下标 **E 核在前、P 核在后**（实测 `ioreg cluster-type`），分组一律走 `splitCores` | 大小核、异构核 |

## 关键事实（易错点）

- 数据库金额一律 **CNY**（USD 在写入前经 `CurrencyConfig` 转换）
- 剪贴板数据落库后发 `AppEvents.postClipboardChanged()`，UI 订阅后立即刷新
- `NetworkMonitorCore` 禁止 import AppKit；依赖方向 App → Core
- 测试：`swift run --disable-sandbox --build-system native TestRunner`，内存 SQLite，无 XCTest
- Open Design 额度接口只认浏览器 Cookie（`__Secure-better-auth.session_token`），Bearer 一律 401；用量接口只接受最近 7 天窗口（超窗或终点在未来都 400 `invalid_workspace_usage_time_range`），**汇总必须读顶层 `summary` / `totalCount`，不要翻页**
- 系统监控：CPU 功耗恒为 0（不可得）、风扇转速在 Apple Silicon 不可得，UI 用「—」表达，**不填假值**
- 磁盘速率必须按 `IORegistryEntryGetRegistryEntryID` 配对（按数组索引会串号出负速率）；内存页大小用 `host_page_size()` 动态取（Apple Silicon 16KiB / Intel 4KiB）
