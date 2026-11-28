# 开源项目「组装式架构」调研（只读）

- 任务：为 toolbar（macOS 菜单栏监控 App，Swift 6 / SwiftPM 五 target / 无第三方依赖 / ~11.5 万行）挑可直接借鉴的组装范式
- 手段：只读 web 检索（GitHub raw / API + 本机 7890 代理）。**未构建、未改仓库任何既有文件**
- 结论一句话：**别做"运行时插件发现"，做"静态清单 + 编译期门禁"**。三份可抄的骨架是 stats（Module 基类 + 声明式 config.plist）、sindresorhus/Settings（pane 数组 + SettingsPane 协议）、swift-testing（编译期写段的极端形态，用来证明 Swift 没反射也能注册，但**本项目不该抄它**）。TCA 的 ReducerBuilder 组合是"组合"不是"注册"，与本次目标正交。

---

## 1. Swift / macOS 生态：真实项目怎么注册与装配

### 1.1 exelban/stats（与本项目最像：菜单栏 + 多监控模块）

**机制：Module 基类（模板方法）+ Reader 协议 + 每个模块一份 config.plist 声明**

| 关注点 | 做法 | 证据 |
|---|---|---|
| 模块边界 | 每个监控项一个 **Xcode framework target**：`Modules/CPU`、`Modules/Net`、`Modules/RAM`…，各自 `main.swift` 里 `public class CPU: Module` | https://github.com/exelban/stats/tree/master/Modules ；`Modules/CPU/main.swift`（`public class CPU: Module`） |
| 通用骨架 | `open class Module` 提供 `mount() / unmount() / enable() / disable() / terminate() / setReaders()`，子类只覆写 `willTerminate()`、`isAvailable()` 等钩子 | `Kit/module/module.swift:194-260` |
| 采集器注册 | `setReaders(_ list: [Reader_p?])` + `protocol Reader_p { setup/read/start/pause/stop/lock/unlock/setInterval }`，同一模块挂多个 reader（CPU 挂 6 个：Load/Process/Temperature/Frequency/Limit/AverageLoad） | `Kit/module/reader.swift`；`Modules/CPU/main.swift` 里的 `loadReader/frequencyReader/...` |
| **UI 贡献点 = 声明文件** | 每个模块目录下 `config.plist` 声明 `Widgets`（label/mini/line_chart/bar_chart/pie_chart/tachometer/icon + 每个的 `Default`/`Order`/`Preview`）、`Settings.popup`、`Settings.notifications`、`Summary.menu_bar`；`module_c.init(in path:)` 读 plist 生成 `availableWidgets / defaultWidget / hasPreview / hasSummary` | `Modules/CPU/config.plist`；`Kit/module/module.swift:20-80`（`public struct module_c { init(in path:) }`） |
| 装配在哪 | **一行一个模块的中心数组**：`var modules: [Module] = [CPU(), GPU(), RAM(), Disk(), Sensors(), ...]`，启动时 `modules.reversed().forEach { $0.mount() }`，退出时 `modules.forEach { $0.terminate() }` | `Stats/AppDelegate.swift:26-38`（数组）、`:80`（mount）、`:106`（terminate） |
| 加一个新模块要动几处 | **3 处**：① 新建 `Modules/Xxx/` 目录 + framework target（`main.swift` / `config.plist` / 可选 `popup.swift``settings.swift``readers.swift`）；② `AppDelegate.swift` 的 `modules` 数组加一行；③ Xcode target 依赖。**UI 的 widget / settings / notifications 开关全在 plist 里，宿主代码零改动**——这是最值钱的一条 | 上述三处 |

**可抄的本质**：宿主只认两样东西——`Module` 协议（生命周期契约）和 `config.plist`（贡献点声明）。新增功能对宿主的改动收敛到**一行数组**。

### 1.2 jordanbaird/Ice（反面参考：加一个设置面板要动 4 处）

- `SettingsNavigationIdentifier` 枚举 + `SettingsView.swift` 里 **`switch` 全枚举**（`case .general: GeneralSettingsPane()` …），SwiftUI `NavigationSplitView` 侧栏 `ForEach(allCases)`
- `SettingsManager` 里**手写** `generalSettingsManager / advancedSettingsManager / hotkeySettingsManager` 三个字段 + `performSetup()` 三行调用
- 加一个面板 = 枚举加 case + switch 加 case + 新建 Pane + Manager 里加字段与 setup 调用（**4 处**）
- 证据：https://github.com/jordanbaird/Ice/blob/main/Ice/Settings/SettingsView.swift ；`Ice/Settings/SettingsManagers/SettingsManager.swift`

**结论**：Ice 是"能跑但没组装化"的样本，正好是 toolbar 现状的同构体（手写顺序装配 + 全枚举 switch）。它可信地说明：**只靠协议 + 枚举，装配不会自己长出来。**

### 1.3 sindresorhus/Settings（最小可抄的"pane 数组"范式）

- 面板实现 `protocol SettingsPane`：`paneIdentifier`（唯一 id）/ `paneTitle` / `toolbarItemIcon` 三个必须项
- 装配就一次：`SettingsWindowController(panes: [GeneralSettingsViewController(), AdvancedSettingsViewController()], style: .toolbar)`
- Maccy 用同款：扩展 `Settings.PaneIdentifier` 声明 `advanced/appearance/general/ignore/storage` 五个静态 id，pane 类各自实现协议
- 证据：https://github.com/sindresorhus/Settings/blob/main/Sources/Settings/SettingsPane.swift ；`Sources/Settings/SettingsWindowController.swift` ；https://github.com/p0deje/Maccy/blob/master/Maccy/Extensions/Settings.PaneIdentifier+Panes.swift
- **加一个面板 = 1 处**（数组加一行 + 新增一个类）

### 1.4 pointfreeco/swift-composable-architecture（"组合"≠"注册"）

- 核心是 `ReducerBuilder` 结果构建器 + `CombineReducers { ReducerA(); ReducerB(); ReducerC() }`——父级显式列出子 reducer，**每个 feature 仍要在父级写一行**，没有反射没有注册表
- 证据：https://github.com/pointfreeco/swift-composable-architecture/blob/main/Sources/ComposableArchitecture/Reducer/Reducers/CombineReducers.swift （`:1-30` 的 doc 与 `@ReducerBuilder`）
- **对 toolbar 的判断**：TCA 解决的是"状态与副作用的组合"，不是"装配接线"。它的 `ReducerBuilder` 手法（结果构建器把 N 行收敛成声明式块）可抄成注册表的 API 形状；整套 TCA 引进来是**引入第三方依赖 + 重写 UI 层**，与约束和目标都不合，不推荐。

### 1.5 tuist/tuist 的 ProjectDescription（声明式清单 + 宿主生成）

- 仓库根 `Project.swift` 直接 `import ProjectDescription`，用 Swift 代码（`Target(...)` / `.executionAction(...)`）写清单，tuist 读取后**生成 Xcode 工程**
- 证据：https://github.com/tuist/tuist/blob/main/Project.swift （`import ProjectDescription / import ProjectDescriptionHelpers`，`let baseSettings: SettingsDictionary`）
- **可抄的点**：清单是**真 Swift 代码**（能被编译器与 IDE 校验、能写循环与 if），不是 JSON/YAML —— 比 stats 的 plist 更强，比 VS Code 的 package.json 更适合 toolbar。

---

## 2. 跨语言范式：讲透机制

### 2.1 声明式插件清单（VS Code / IntelliJ）→ Swift 怎么落地

**机制**：功能不写代码注册，写**清单**；宿主启动时只读清单，再按需回调实现。

| 系统 | 清单 | 宿主怎么读 | 激活时机 |
|---|---|---|---|
| VS Code | `package.json` 的 `contributes`（commands / menus / views / configuration / colors…） | 扫描扩展目录读 JSON，**用户没触发就不加载扩展代码** | `activationEvents`（`onCommand:` / `onView:` …）——**声明与实现在时间上解耦** |
| IntelliJ | `META-INF/plugin.xml` 的 `<extensions defaultExtensionNs="com.intellij">`（`<toolWindow factoryClass=... id=.../>`、`<postStartupActivity implementation=.../>`） | 类名当字符串存，**用到才 Class.forName** | 由扩展点自己决定 |

- 证据：https://github.com/microsoft/vscode-docs/blob/main/api/references/contribution-points.md （`contributes` 字段与可用点清单）；https://github.com/microsoft/vscode-docs/blob/main/api/references/activation-events.md ；https://github.com/JetBrains/intellij-platform-plugin-template/blob/main/src/main/resources/META-INF/plugin.xml （`<extensions>` 里 `factoryClass`/`implementation` 都是**类名字符串**）

**Swift 里没有 bundle 扫描怎么办**（关键回答）：
1. **清单不一定要是 JSON**。把"清单"做成 **Swift 静态数组**（tuist 式），编译期就能被类型检查——vs Swift 反射扫描 bundle 那条路根本走不通（Swift 没有 `NSClassFromString` 之外的运行时类型枚举，且 App 包内模块是静态链接的，扫不出"插件目录"）。
2. **把"声明"和"实现"用协议 + 闭包拆开**：清单里存 `() -> any PanelTab`（延迟构造），天然等价于 VS Code 的 activationEvents —— 懒装配在清单层面就是一行 `lazy` 闭包，不用另造机制（toolbar 的"懒装配"现状可以直接提升成清单能力）。
3. **没有类名字符串就换成 id 字符串**：IntelliJ 存 `factoryClass="..."`，Swift 存 `id: "billing.claude"` + 构造闭包，效果相同且类型安全。

### 2.2 编译期注册表（Rust inventory / C++ 静态初始化）→ Swift 有没有等价物

**Rust 机制**：`inventory::collect!(Flag)` 定义注册表类型，任意 crate 里 `inventory::submit! { Flag::new('v', "verbose") }`，**链接器把记录塞进一段，运行时遍历**——不需要中心列表。
- 证据：https://github.com/dtolnay/inventory （README：`collect!` / `submit!`，"There does not need to be a central list of all the plugins"）

**Swift 确实有等价物，而且是官方在用的**：swift-testing 把测试记录**编译期写进 Mach-O 段** `__DATA_CONST,__swift5_tests`（ELF 是 `swift5_tests`，PE 是 `.sw5test$B`），运行时扫段发现，记录布局是 `(kind, reserved1, accessor, context, reserved2)` 的 C 结构 + `@convention(c)` accessor。
- 证据：https://github.com/swiftlang/swift-testing/blob/main/Documentation/ABI/TestContent.md （段名表 + Record layout + C 定义）；`Sources/_TestDiscovery/TestContentRecord.swift`、`Sources/_TestDiscovery/DiscoverableAsTestContent.swift`（`public protocol DiscoverableAsTestContent: Sendable`，注释原文 "stored in the test content section of a Swift binary at compile time, and dynamically discovered at runtime"）

**但对 toolbar 的判断：不抄。** 理由（这是本次调研最重要的一条取舍）：
- 该机制依赖 **C 侧 `__attribute__((section(...)))` + 每平台链接器差异**（swift-testing 自己为此写了 Windows 的 padding 兼容与 `WinSDKAdditions.swift`）——等于给无第三方依赖的仓库引入一个 C shim target + 各平台分支。
- 它换来的是"**跨 crate 无中心列表**"，收益针对的是**千级贡献者/多团队**场景；toolbar 是单仓单 app、模块十几个，中心列表（一行一个）反而可读、可 diff、可被门禁脚本校验。
- 静态初始化的隐藏成本：Swift 的全局初始化顺序不确定，把 UI/权限/网络的构造放进静态初始化会制造难复现的启动顺序 bug。

### 2.3 依赖注入容器：何时值得引入，何时是负资产

| 方案 | 机制 | 成本 | 证据 |
|---|---|---|---|
| Swinject | 运行时容器 `Container.register/resolve` + `Assembler` 分模块组装 | 运行时字符串/类型键解析，错误在运行期才炸；需引依赖 | https://github.com/Swinject/Swinject （README Features: Object Scopes / Container Hierarchy / Modular Components） |
| Needle | **代码生成**，编译期校验依赖图，"If it compiles, it works" | 需构建期跑代码生成器（第三方二进制） | https://github.com/uber/needle （README：hierarchical DI + code generation + compile-time safety） |
| Factory | 每个依赖一个 `Factory<T>` 计算属性，`Container` 作用域，~1000 行 | 纯 Swift、无构建期脚本；仍是运行时解析 | https://github.com/hmlongco/Factory （README："under 1,000 lines of executable code"、"no compile-time scripts or build phases"） |

**判断线（给 toolbar 的口径）**：
- **值得引入**：依赖图有分层作用域、有大量测试替身需求、组件由多个团队并行开发。→ toolbar 都不满足（4 类依赖：logger / storage / http / clock）。
- **负资产**：容器成为第二个 `AppContext.shared`——把 165 处 `AppContext.shared` 换成 165 处 `Container.resolve()`，只是把编译期错误挪到运行期，还多一层间接。**这正是 toolbar 现在的病，不是解药。**
- 结论：**不引容器。** 用"模块声明里的显式 `dependencies: [String]` + 装配器按 id 拓扑排序注入"，把依赖关系变成**清单里的数据**（可 grep、可门禁），而不是运行期查找。

---

## 3. 「无第三方依赖」约束下的取舍

| 方案 | 能否纯手写 | 代码量估计 | 建议 |
|---|---|---|---|
| 静态模块清单（Swift 数组 / tuist 式） | ✅ | 80–150 行 | **采纳** |
| 贡献点协议 + 类型化注册表 | ✅ | 100–180 行 | **采纳** |
| 布局/装配器（按 id 解析 + 顺序 + 生命周期） | ✅ | 100–150 行 | **采纳** |
| 编译期门禁（清单 ↔ 目录一致性、贡献点 id 唯一性） | ✅ 用 **SwiftPM build tool plugin**（`BuildToolPlugin.createBuildCommands` 返回 `.buildCommand`）：https://github.com/swiftlang/swift-package-manager/blob/main/Examples/swift-sdl/Plugins/SwiftSDLGenPlugin/SwiftSDLGenPlugin.swift | 60–120 行 | **采纳**（本仓代码，不是第三方依赖） |
| 运行时反射/段扫描自动注册 | ❌ 需 C shim + 平台分支 | 300+ 行且脆弱 | 不采纳 |
| DI 容器（Swinject / Factory / Needle） | 部分可手写 | 500–1000 行 | 不采纳（可手写的等价物就是上面的装配器） |
| 代码生成清单（tuist 式外部工具） | 需外部工具链 | — | 不采纳（用 SwiftPM plugin 替代，避免引工具） |

**总手写预算：≤ 400 行**（清单 + 贡献点 + 装配器 + 门禁 plugin），落在"≤300 行"量级附近，符合无依赖约束。

---

## 4. 落地方案：toolbar 的组装式骨架

### 4.1 贡献点（Contribution Point）清单（8 个，先做 5 个）

| 贡献点 | 契约（返回什么） | 现状对应 | 优先级 |
|---|---|---|---|
| `panelTab` | `(id, order, title, () -> NSViewController)` | MenuPanel 15830 行的五个 tab | P0 |
| `settingsSection` | `(id, group, order, title, icon, () -> NSViewController)` | Settings 8387 行的十一分类 | P0 |
| `billingProvider` | `BillingProvider` 协议实现 + 元数据（kindID、supportsUsage、窗口种类） | **已有协议 + 注册表**，最成熟，是首个迁移样本 | P0 |
| `notificationEvent` | `(NotificationEvent, 默认开关, 提示音 cue, 可用提醒方式)` | 七类事件 + 偏好键 `notify.<event>.<field>` | P1 |
| `menuBarMetric` | `(id, order, 单位, 采样闭包, 渲染闭包)` | 17 项菜单栏指标 | P1 |
| `hookEventHandler` | `(event, priority, handler)` | AppEvents 热生效的散落订阅 | P2 |
| `snapshotProbe` | `(screenID, 固定帧尺寸, 取数闭包)` | 当时的 `NM_SNAPSHOT_FREEZE` 快照通道（已删除；页面取证现走 `nmcli page`） | P2 |
| `testSuite` | `(suiteID, 依赖的模块 id)` | TestRunner | P2 |

### 4.2 模块声明长什么样（20 行内示意）

```swift
// Core/Assembly/ModuleManifest.swift
public struct ModuleManifest: Sendable {
    public let id: String                       // "billing.claude"
    public let dependencies: [String]           // 装配顺序由它拓扑排序
    public let contributions: [Contribution]    // 一个模块可贡献多处
    public let start: @Sendable (ModuleContext) throws -> Void   // 等价 mount()
}

// Billing/Claude/ClaudeModule.swift —— 新功能只写这个文件
enum ClaudeModule: ModuleDeclaring {
    static let manifest = ModuleManifest(
        id: "billing.claude",
        dependencies: ["http.client", "storage.secure"],
        contributions: [
            .billingProvider(id: "claude", make: { ClaudeBillingProvider() }),
            .settingsSection(id: "billing.claude.creds", group: .billing, order: 20,
                             make: { ClaudeCredentialSection() }),
        ],
        start: { ctx in try ctx.require(ClaudeBillingProvider.self).warmUp() }
    )
}
```

扩展点 `ModuleDeclaring` 是**空的 marker 协议**，唯一用途是让门禁脚本/plugin 能 grep 到"哪些类型声明了 manifest"。

### 4.3 注册与装配机制：**编译期静态清单 + SwiftPM 门禁**（不用链接段、不用代码生成）

```swift
// App/Assembly/ModuleCatalog.swift —— 全仓唯一的装配清单，一行一个模块
@MainActor enum ModuleCatalog {
    static let all: [any ModuleDeclaring.Type] = [
        CoreModule.self, HTTPModule.self, StorageModule.self,
        BillingClaudeModule.self, BillingCodexModule.self,
        ClipboardModule.self, TokenModule.self, SystemModule.self,
    ]
}
```

**为什么选它**（三条硬理由）：
1. **可校验**：清单是 Swift 代码，拼错类型编译不过；plist/JSON 清单做不到。
2. **可门禁**：build tool plugin 读 `Sources/**/*Module.swift` 与 `ModuleCatalog.swift`，断言"每个 `ModuleDeclaring` 都出现在清单里、每个 id 唯一、依赖 id 存在、贡献点 id 无重复"——**新增模块漏注册会在编译期失败**，这是 stats 的数组方案缺的一环（它漏注册是静默的）。
3. **可读、可 diff**：十几个模块的中心列表不是负担，是装配文档本身；inventory 那种"无中心列表"针对的是千级贡献者场景。

**装配器（唯一允许知道顺序的地方，~120 行）**：
```swift
@MainActor final class Assembler {
    func boot(_ types: [any ModuleDeclaring.Type]) throws {
        let manifests = types.map { $0.manifest }
        try validate(manifests)                       // 重复 id / 缺失依赖 / 循环依赖
        for m in topologicalSort(manifests) {         // 依赖优先，同层按 id 稳定排序
            try m.start(context(for: m))              // 只构造，不做 IO
            register(m.contributions)                 // 进对应贡献点注册表
        }
    }
}
```

**与 stats 的差异（改进点）**：stats 的 `Module.mount()` 里既 `startReaders()` 又 `menuBar.enable()`（构造 + 副作用混在一起）；本骨架把 `start()` 限制为"只做构造与注册"，**实际首帧渲染交给贡献点的懒装配闭包**（正好复用 toolbar 已有的"懒装配"能力）。

### 4.4 与 SwiftPM target 边界的配合

**建议：保持 5 target 不扩，把契约下沉到 Core/UI 两层。**

| 层 | 放什么 | 理由 |
|---|---|---|
| Core | `ModuleManifest` / `Contribution` / `ModuleContext` / `Assembler` / `BillingProvider` 等**契约**，以及所有纯逻辑模块声明 | Core 已是纯逻辑无 AppKit 依赖的部分（Billing 3 家 provider 就在 Core） |
| UI（纯逻辑） | `panelTab` / `settingsSection` / `menuBarMetric` 的**布局与状态机**，返回视图模型的构造闭包 | 保持可测 |
| App | `ModuleCatalog` + `Assembler` 实例 + 各贡献点的 **NSViewController 工厂**（唯一碰 AppKit 的地方） | 组合根只此一处 |
| TestRunner | `testSuite` 贡献点的消费者 | 已有 |

**不拆更多 target 的理由（反例警告）**：11.5 万行跨 target 会把大量 `internal` 逼成 `public`，public API 表面爆炸且每次重命名都要改边界——收益（编译增量）远小于成本。stats 用 framework-per-module 是因为它要发 widget 扩展；toolbar 是单一 app。

### 4.5 迁移路径（4 步，第一步就见效）

| 步 | 动作 | 验收信号 |
|---|---|---|
| **0（先决）** | **拆 `AppContext.shared` 的 44 处 storage 与 112 处 logger**：改成 `ModuleContext` 注入（构造参数或 `ctx.storage/ctx.log`）。这一步单独做，因为它挡在所有模块化前面 | `grep -rc "AppContext.shared" | 从 165 降到 ≤ 单例自身的 1 处` |
| **1** | 落 `ModuleManifest` / `Contribution` / `Assembler` / `ModuleCatalog` 四件套（≤400 行，无 UI 改动） | 现有 AppCoordinator 的 14 条链路中，**至少 billing 9 个 provider 通过新注册表装配**（它已有协议 + 注册表，改造最小） |
| **2** | 迁移贡献点，一个点一个 PR：`billingProvider` → `settingsSection` → `panelTab` → `notificationEvent` → `menuBarMetric` | 每迁一个点，AppCoordinator 少一条手写链路；新功能 PR 的 diff 里**不再出现 AppCoordinator** |
| **3** | 加 SwiftPM build tool plugin 门禁（清单 ↔ 声明一致性、id 唯一、依赖存在、循环依赖） | 故意删掉一行清单 → 编译失败（负向验证） |

**第一步就要做的**：**步 0 的 `AppContext.shared` 拆解 + 步 1 的 billing 样本**。理由：billing 是唯一已有"协议 + 注册表"的链路，用它验证骨架，失败成本最低；而 `AppContext.shared` 不先拆，任何注册表都只是给单例换了个名字。

---

## 5. 反例：组装式过度设计的翻车点

| # | 翻车点 | 机制 | toolbar 的触发条件 |
|---|---|---|---|
| 1 | **贡献点爆炸** | 每个新功能都想开一个新 point 类型，最后 30 个 point、每个 1 个实现，读者要在 30 份契约里找 | 单点实现数 ≤1，或 point 总数 >12 时立刻合并回 8 个 |
| 2 | **注册表变成第二个全局单例** | 用 `Registry.shared.resolve(...)` 替换 `AppContext.shared`，165 处单例变成 165 处查找，错误从编译期挪到运行期 | 出现任何 `Registry.shared` / `Container.resolve` 的调用点 >0；判据：注册表**只允许 Assembler 写**，业务代码不得读 |
| 3 | **装配期做副作用** | `start()` 里读钥匙串 / 发网络 / 申请权限 / 建窗口，启动变慢且失败栈深埋在拓扑排序里 | 启动耗时或 `start()` 里出现 IO；判据：`start()` 只允许构造，副作用全部下放到贡献点闭包的懒执行 |
| 4 | **为模块化拆 target 拆爆 public API** | 跨 target 逼所有 internal 变 public | 新增 target 后 public 符号数显著上升；判据：**不新增 target**，用目录 + 协议隔离 |
| 5 | **追求运行时动态发现** | 想学 VS Code 扫插件目录 / 学 inventory 无中心列表，在 Swift 里做 dlopen 或 C 段扫描 | 出现 C shim target、`__attribute__((section))`、平台 `#if` 分支；判据：**单仓单 app 永远不触发** |
| 6 | **清单与实现漂移** | 声明在 plist/JSON、实现在 Swift，改名后两边不同步、无声失败 | 没有编译期门禁；判据：必须做步 3 的 plugin 门禁，否则宁可用纯 Swift 清单 |

---

## 6. 不确定项 / 没验到的

1. **stats 的 `modules` 数组是否真为全仓唯一装配点**：只读到 `AppDelegate.swift:26-38/80/106` 与 `Kit/module/module.swift` 生命周期；未逐文件确认 `MenuBar`/`Window` 是否另有旁路注册。
2. **swift-testing 的段扫描是否有 Swift 侧公开写法**：`Documentation/ABI/TestContent.md` 只给 C 结构与段名，未找到纯 Swift 声明 section 的方法；结论"需 C shim"基于该文档未提供 Swift 方式，**未做编译实验验证**。
3. **SwiftPM build tool plugin 能否可靠读取 Sources 目录做一致性校验**：只按 `SwiftSDLGenPlugin` 的 `createBuildCommands` 形态推断（plugin 能拿到 `PluginContext`/`Target` 与工具路径）；**未实际编译验证**在 toolbar 的 Package.swift 上是否可用。
4. **tuist 文档站** 抓取返回 301（重定向），本次未跟；只用仓库根 `Project.swift` 作为声明式清单的证据。
5. **本项目 14 条链路的精确清单**未复核（按任务说明为已确认事实，未去仓库验证）。
