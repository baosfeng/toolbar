# 组装式架构契约（冻结版 v1）

> 本文件是三个并行实现分支的**唯一契约**。实现方只读本文件 + 项目编码规范，不自行改架构。
> 现状证据见同目录 `data-layer.md` / `network-layer.md` / `ui-assembly.md` / `engineering.md`。

## 0. 目标（用户口径）

「后续开发像组装组件一样——只实现功能，装配 / 接线 / 门禁由框架承担。」

落地为四条硬约束：

1. **一个功能 = 一份声明**（Module）；装配层只认声明，不认识具体类型。
2. **扩展 = 新增文件 + 一行注册**，不改任何既有 switch / 字典 / 硬编码清单。
3. **能力收口**：数据库事务、HTTP 请求、迁移、UI 页面骨架各有唯一出口。
4. **记账靠注册表自洽断言**，不靠人手维护的计数（加一个模块不再改测试里的数字）。

## 1. 分层（依赖只能向下）

```
NetworkMonitorCore   领域 + 基础设施（禁 AppKit）    ← 新增 HTTPTransport / Transaction / MigrationRegistry
NetworkMonitorUI     纯值声明 + 纯逻辑（禁 AppKit）  ← 新增 *Descriptor / ContributionPoint（无闭包、无 AppKit 类型）
NetworkMonitor       AppKit 视图 + 装配（唯一组合根） ← 新增 *Module（= Descriptor + 工厂闭包）/ *Registry / AppComposition
```

**Descriptor 与 Module 分开的理由**：`makePane: () -> NSView` 带 AppKit 类型，不能进 UI target（TestRunner 要能断言 descriptor 的纯口径）。Descriptor 是可测的真源，Module 是 App 侧的装配件。

## 2. 三条 Contributor 契约

### 2.1 面板分页（PaneModule）

```swift
// NetworkMonitorUI/PaneModuleDescriptor.swift —— 纯值
public struct PaneModuleDescriptor: Sendable, Equatable {
    public let id: String            // 稳定 id，必须 ∈ PanelTabCatalog.stableIDs
    public let title: String         // 分段条文字
    public let symbolName: String    // 分段条图标
    public let snapshotSuffix: String // 快照文件名后缀
    public let evidenceKey: String   // 取证标识（历史上是 NM_EVIDENCE_TAB 的取值；探针已删除）
    public let sortIndex: Int        // 声明序 = 默认序
}

// NetworkMonitor/MenuPanel/PaneModule.swift —— App 侧装配件
@MainActor public struct PaneModule {
    public let descriptor: PaneModuleDescriptor
    public let makePane: () -> MenuPanelPaneView
    public let firstDisplay: (MenuPanelController, MenuPanelPaneView) -> Void   // 首屏补数据
    public let bindActions: (MenuPanelPaneView, MenuPanelController) -> Void    // 挂回调
    public let applySnapshot: (MenuPanelPaneView, PaneDataSnapshot) -> Void     // 数据刷新
    public let dataNeeds: Set<PaneDataNeed>
}
```

**取代的 7 处穷尽 switch**：`MenuTabBarView` 的 title / stableID / symbol（3）、`MenuPanelView+Panes` 的 ensurePaneLoaded（1）、`MenuPanelController.configure(pane:for:)`（1）、`+Actions.refreshPaneFirstDisplay`（1）、`MenuPanelSnapshot.fileNameSuffix` + `MenuPanelEvidence` 环境变量映射（2，改由 descriptor 字段驱动）。

**注册表** `PaneModuleRegistry`（App target）：`register(_:)` / `module(for id:)` / `all`（按 sortIndex）。组合根一次注册 5 个模块。

### 2.2 设置分类（SettingsModule）

同构，字段：`id / title / symbolName / subtitle / fileSuffix / group`（group ∈ `SettingsSidebarGroup`）+ `makePane: () -> SettingsPaneView`。取代 `SettingsSection` 的 4 个 switch 与 `AppCoordinator+Settings` 的 factories 字典字面量。

### 2.3 数据能力（DataModule）

```swift
// Core：真正的事务原语（取代 6 文件 20 处手写 BEGIN/COMMIT）
public protocol DatabaseService {
    func withTransaction<T>(_ body: (any SQLiteConnection) throws -> T) throws -> T
}
// Core：迁移登记表（取代 migrateIfNeeded() 的 2 行硬编码）
public protocol SchemaMigration: Sendable {
    var identifier: String { get }      // 稳定 id，写进 migration_log
    var order: Int { get }              // 必须唯一、单调
    func migrate(_ db: OpaquePointer) throws
}
public final class MigrationRegistry { register(_ m: any SchemaMigration); func runAll(on:) throws }
```

**铁律**：一个业务动作 = 一个事务。删板（`deleteBoard`）必须原子：删条目 + 删板行在同一事务里。

### 2.4 网络能力（HttpModule，第三批）

```swift
public struct Endpoint<Response: Decodable & Sendable>: Sendable {
    let method: HTTPMethod; let url: URL; let headers: [String: String]
    let body: Data?; let timeout: TimeInterval; let decoder: @Sendable (Data) throws -> Response
}
public protocol HTTPTransport: Sendable {   // Core 唯一实现，App 的 BillingHTTPClient 下线
    func send<Response>(_ endpoint: Endpoint<Response>) async throws -> Response
}
```

## 3. 装配（AppComposition）

`AppCoordinator.start()` 的 14 阶段手写顺序 → `AppComposition`：

```swift
public struct AssembleStage {
    let name: String
    let requires: [String]              // 依赖的阶段名
    let run: (inout AppEnvironment) throws -> Void
}
```

- 按 `requires` 做拓扑排序，缺依赖 / 成环 = **启动即失败并 log.error**（现在是靠注释与代码位置维持顺序，静默错位）。
- 每条链路 = 一个 `AssembleStage`；新增模块 = 新增一个 stage + 声明 requires。

## 4. 门禁（与实现同步交付）

| 门禁 | 做法 | 判据 |
|---|---|---|
| 校验注册表自洽 | 测试：`registry.all.count == PanelTabCatalog.stableIDs.count` 且顺序一致 | 加 tab 不再改数字 |
| 禁止样板 switch 回流 | `Scripts/check-arch-guards.sh`：`MenuPanelTab`/`SettingsSection` 上不得再出现 title/symbol 穷尽 switch | exit 0 |
| 依赖方向 | 同一脚本：Core 禁 `import AppKit`；UI 禁 AppKit | exit 0 |
| 禁 print / 禁直读 UserDefaults.standard | 同一脚本（白名单 + 豁免理由） | exit 0 |
| 事务唯一出口 | 测试：`BEGIN/COMMIT` 字面量只允许出现在 `DatabaseTransaction.swift` | 其余文件 0 命中 |

## 5. 迁移顺序（谁先谁后）

1. **PaneModule + SettingsModule**（arch-pane-modules）——用户「加功能」最高频路径，且不碰数据层。
2. **Transaction + MigrationRegistry + 删板原子化**（arch-data-tx）——数据一致性唯一硬缺陷。
3. **HttpTransport**（第三批）——6 实现 17 出网点收敛；依赖 1、2 稳定后再动。
4. **AppComposition**（第四批）——收掉手写顺序装配；依赖 1–3 全部 Module 化之后才有意义。

**并行冲突边界**：1 只动 `MenuPanel/`、`Settings/`、`NetworkMonitorUI/`、`AppCoordinator+Settings.swift`；2 只动 `NetworkMonitorCore/DatabaseManager*`、`Clipboard*`、`Harness*`、`ClipboardSchema*`。两者文件集不相交（`AppCoordinator.swift` 归 1，`AppCoordinator+Clipboard.swift` 归 2）。

## 6. 反例（别做）

- 不要为「统一」引入 DI 容器 / SwiftUI / 第三方库（零依赖是硬约束）。
- 不要把 Descriptor 做成带闭包的类型（进不了 UI target，测试够不着）。
- 不要一次改所有页面——先让 5 个分页走注册表，等价性用现有快照对比证明后再动内部。
- 不要靠改名或拆文件规避行数门禁（现存 5 处已确认的规避要随本次一并澄清，见 data-layer.md §2.2）。
