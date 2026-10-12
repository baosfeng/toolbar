---
name: toolbar-coding-standards
description: 本项目（toolbar/NetworkMonitor）专属编码规范：架构原则、文件组织、测试与提交纪律，写代码前必加载
---

# 项目编码规范（NetworkMonitor / macMonitor）

本项目（`<repo>`）专属编码规范 playbook。**在编写或修改本项目任何 Swift 代码之前，必须先加载本 skill 并遵循全部原则。** 本规范由架构审查（2026-08）固化，违反任一强制原则的代码应被拒绝。

## 项目速览

- Swift 6.3（swiftLanguageModes: [.v6]），SwiftPM 三目标：
  - `NetworkMonitorCore`（库，**禁止 import AppKit**）— 领域协议、数据库、统计、模型、事件分发、格式化
  - `NetworkMonitor`（可执行）— UI、Hook 监听器、事件处理器、监控实现（AppKit 仅限此目标）
  - `TestRunner`（可执行）— 手写断言测试（本机无 Xcode SDK，不用 XCTest）
- 构建：`cd NetworkMonitor && swift build --disable-sandbox`
- 测试：`cd NetworkMonitor && swift run --disable-sandbox TestRunner`（须显示「🎉 所有测试通过！」）
- 打包：`cd NetworkMonitor && ./Scripts/build-app.sh`（部署到 /Applications 并自动启动）

## 必读文档（操作前）

- 改代码 → 本 skill（规范权威来源）+ `docs/开发指南/构建与测试.md`
- 改文档 → `docs/开发指南/文档规范.md`
- 提交 → `docs/开发指南/提交规范.md`
- 查代码 → 必须用 codebase-memory MCP 知识图谱，禁止直接 grep/glob/lsp
- 规范更新 → 一律写入本 skill，**禁止另建独立规范文档**

## 架构分层与依赖方向

```
main.swift → AppDelegate → AppCoordinator（组合根，唯一允许 new 具体类的地方）
  → MenuBarManager（UI，构造器注入协议）
  → ReasonixHookMonitor（UDS 监听）→ HookEventDispatcher（注册表）→ HookEventHandler 实现
  → 数据层：DatabaseService / HookEventRepository / TokenUsageRepository（AppDatabase 组合）
```

依赖方向：`NetworkMonitor → NetworkMonitorCore`，Core 绝不反向依赖。协议全部定义在 `Sources/NetworkMonitorCore/Domain/Protocols/`。

## 强制原则（Code Review 硬门槛）

### 1. 依赖倒置（DIP）
- 调用方只依赖协议：`any DatabaseService`、`any AppDatabase`，禁止依赖 `DatabaseManager` 等具体类
- `AppCoordinator` 是唯一组合根；组件一律构造器注入，禁止内部 `DatabaseManager()` / `UserDefaults.standard` 等自行获取

### 2. 接口隔离（ISP）
- 一个协议一个领域；新领域新建协议文件，禁止往 `DatabaseService` 等现有协议塞方法
- 数据库三协议：`DatabaseService`（连接/query/close）、`HookEventRepository`（Hook 写入查询）、`TokenUsageRepository`（token 写入）；组合用 `AppDatabase`

### 3. 单一职责（SRP）
- 单文件 >500 行 / 15 KiB（15360 字节）必须拆分；存量超标文件不追溯整改，仅在改动该文件时顺带治理
- 拆分范式：主类文件（连接/迁移/建表）+ `类名+协议名.swift` 扩展文件（`extension DatabaseManager: HookEventRepository`）
- conformance 声明在扩展文件；跨文件访问成员时 private 放宽为 internal 并注释原因

### 4. SPI 扩展（可插拔）
- 新增事件处理 = 实现 `HookEventHandler`（`handledTypes` 空集 = 全部事件）+ `dispatcher.register`；**禁止改** `ReasonixHookMonitor` 核心
- 新增事件类型 = 扩展枚举 + 新处理器，禁止在分发核心加 if 链
- 处理器注册顺序：落库 → 工具调用 → 通知 → stats 同步

### 5. 基础设施注入
- 禁止直读 `UserDefaults.standard`；用 `KeyValueStorage`（`AppContext.shared.storage` 或注入）
- 汇率等可配置项走注入存储（`CurrencyConfig.shared` + `storageOverride`），测试用隔离 suite 不得污染全局

### 6. 事件驱动
- 数据落库后 `AppEvents.postHookDataChanged()`；UI 订阅后立即刷新并重置节流计时，禁止只靠长轮询

### 7. 日志
- 禁止 `print`（`ConsoleLogger` 内部除外）；统一 `LoggingService`：error / warning / info / debug
- 组件注入 `logger: LoggingService = AppContext.shared.logger`

## 编码风格

### 命名约定

| 类别 | 规范 | 示例 |
|------|------|------|
| 类名 | PascalCase | `NetworkSpeedMonitor`, `MenuBarManager` |
| 方法名 | camelCase | `poll()`, `formatSpeedShort()` |
| 变量名 | camelCase | `downloadSpeed`, `totalRx` |
| 常量 | camelCase | `formatter`, `statusItem` |
| 枚举 case | camelCase | `.decimal`, `.useAll` |

### 代码风格

- 4 空格缩进、K&R 大括号、`private` 优先、UI 类 `@MainActor`、类 `final`、`// MARK: -` 分段
- 注释**必须中文**；标识符/关键字保留原文；禁止中英文混杂、无意义注释、注释掉的代码
- 使用 `let` 优先于 `var`；单表达式函数省略 `return`；`defer` 处理资源清理；`guard let` / `if let` 处理可选值

### 推荐语法特性（Swift 6.3）

- Swift 6 并发：`@MainActor`、`Sendable` 协议、`any` 存在类型
- `nonisolated deinit`、增强泛型（`some`/`any`）、Raw strings、`///` 文档注释
- 不确定语法是否可用时，先查在线权威文档确认，再写入代码

## 测试纪律

- **新增代码必须配测试**：每新增类/方法在 `Sources/TestRunner/main.swift` 添加断言（`assertEqual`/`assertNotNil`），覆盖正常/边界/异常
- 数据库测试用 `db.initializeInMemory()`；协议可 mock（如 `RecordingHandler` 测 dispatcher）
- 提交前必须 `swift run --disable-sandbox TestRunner` 全绿

## 提交纪律

- 每功能一提交，中文信息：`<type>: <中文描述>`（type: feat/fix/docs/refactor/test/chore）
- 提交前必须 ask 工具经用户确认（会话级豁免一次后自动授权）
- 提交顺序：测试 → 编译 → 打包（如需）→ 提交

## 异常处理规范

- 禁止直接抛出 `Error`/字符串作为异常，必须定义明确异常类型（如 `ReasonixHookError`）
- 异常按领域划分，禁止跨模块混用；禁止吞没异常（catch 后必须 `logger.error` 或重新抛出）
- 不过度细化异常类型，用错误描述区分场景

## 版本号管理

- 语义化版本 `主.次.修订`；版本号定义在 `Info.plist` 与 `build-app.sh`
- 小改动（bug 修复/文档）→ 修订号 +1；新功能 → 次版本 +1；破坏性变更 → 主版本 +1
- 发版流程：全部测试通过 → 更新版本号 → 编译验证 → 提交 → `git tag vX.Y.Z`

## 代码查询规范

- 代码查询/符号搜索/调用关系分析**必须使用 codebase-memory MCP 知识图谱**（`search_graph` / `trace_path` / `get_code_snippet` / `get_architecture`），禁止直接 grep/glob/lsp 做符号搜索
- 原始工具仅限：文件读写（read_file/edit_file）、编译诊断（lsp_diagnostics）、构建测试验证（bash）
- 知识图谱未索引时先 `index_repository`；显著代码结构变更后建议重新索引

## 自查清单（写完代码逐项过）

- [ ] 依赖协议而非具体实现？
- [ ] 未往旧协议塞新方法？
- [ ] 文件未超 500 行 / 15 KiB（15360 字节）？
- [ ] 事件处理走 Handler 注册？
- [ ] 未直读 UserDefaults、未用 print？
- [ ] 数据变更发了 AppEvents？
- [ ] 新增代码配了测试且全绿？
- [ ] 注释全中文、命名规范（PascalCase/camelCase）？
- [ ] 语法特性与 Swift 6.3 匹配？
