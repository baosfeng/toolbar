# 项目上下文（共享语言）

NetworkMonitor / macMonitor — macOS 菜单栏应用。本文档定义项目术语，帮助 agent 用 1 个词代替 20 个词。术语更新时同步维护本文件。

## 核心术语

| 术语 | 定义 | 避免的说法 |
|------|------|-----------|
| **轮次（turn）** | Reasonix 一次「提交 → 完成/失败」的工作单元，事件携带累计 `turns` 计数 | 回合、第几轮对话 |
| **侧车数据（sidecar）** | 会话目录下 `.jsonl.meta` + `.jsonl.telemetry.json` 两个文件，补全事件缺失的 model/topic/tokens/cost | 元数据文件、附带文件 |
| **stats JSONL** | 官方统计文件 `~/.reasonix/stats/YYYY-MM-DD.jsonl`，**Token 统计唯一权威来源** | 统计文件、日志文件 |
| **Hook 事件** | Reasonix 通过 UDS（`/tmp/reasonix-hook.sock`，Datagram）推送的事件（SessionStart/Stop/PreToolUse 等 13 种） | 消息、推送 |
| **会话（session）** | `sessionId` 标识的一次 Reasonix 对话，对应 `hook_sessions` 表一行 | 对话记录 |
| **组合根** | `AppCoordinator`，唯一允许创建具体实现类的地方 | 依赖容器、工厂 |
| **仓储（Repository）** | 按领域拆分的数据库接口：`HookEventRepository` / `TokenUsageRepository` | 数据访问层 |
| **AppDatabase** | `DatabaseService & HookEventRepository & TokenUsageRepository` 组合 typealias，UI/监听器注入用 | 数据库对象 |
| **分层刷新** | 菜单栏更新频率分层：网速 1s / 流量 5s / Token·AI 15s | 定时器策略 |
| **表达式索引** | 与查询完全一致的 `date(列, 时区偏移)` 表达式索引，保证按日统计走索引 | 普通索引 |

## 关键事实（易错点）

- 数据库金额一律 **CNY**（USD 在写入前经 `CurrencyConfig` 转换）；事件中 total_tokens 仅作会话展示，统计以 stats JSONL 为准
- hook 事件处理走 `HookEventDispatcher` 注册表，新增处理逻辑 = 实现 `HookEventHandler`，**禁止修改监听器核心**
- 数据落库后发 `AppEvents.postHookDataChanged()`，UI 订阅后立即刷新（不等 15 秒轮询）
- `NetworkMonitorCore` 禁止 import AppKit；依赖方向 App → Core
- 测试：`swift run --disable-sandbox TestRunner`，内存 SQLite，无 XCTest
