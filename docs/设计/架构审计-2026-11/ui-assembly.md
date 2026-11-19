# UI 层与装配机制审计（只读）

范围：`NetworkMonitor/Sources`，重点 `NetworkMonitor/MenuPanel`、`Settings`、`DrawnUI`、`AppCoordinator*`、`NetworkMonitorUI`。
只读；未跑构建 / 测试（leader 独占）。命令均为只读 grep/sed/wc/ls。

## 结论（先说答案）

- 装配已是**手写顺序装配 + 字典注册表的混合体**：`AppCoordinator.start()` 是 14 阶段手写顺序（有硬依赖注释），设置页与额度 provider 已经是「声明 + 注册」。
- 「新增一个 tab」= 改 **10 个既有文件 + 新建 1 页**，其中 **6 处是每加一次都要抄一遍的样板 switch**（枚举/stableID/图标、懒装配 switch、动作 switch、首屏 switch、数据转发方法、快照后缀、取证环境变量映射）。
- 「新增一个设置分类」= 改 **5 个既有文件 + 新建 1 页 + 改 2 处测试硬编码**，但侧栏分组表 `SettingsSidebarLayout` 已是唯一真源，装配点只剩 `AppCoordinator+Settings` 的一张字典。
- 分层基本守住了：视图**没有** URLSession / DatabaseManager / UserDefaults.standard（0 命中）；泄漏点是「视图直接读业务对象状态」（ProvidersPane、TokenPaneView）与 3 份卡片底绘制公式 + 1 处纯逻辑复制。
- 目标形态可行，且**已有 5 个雏形**；最值得照抄的是 `BillingProviderRegistry`（一个类型 = 实现协议 + 一次 register）与 `SettingsNotificationEventCard`（事件声明 + 每页一行复用）。

---

## 1. 新增功能的接线成本

### 1.1 场景 A：MenuPanel 加一个 tab（如「剪贴板」再回来）

必须改动的既有文件（10）+ 新建（1）：

| # | 文件:行 | 要改什么 | 是否样板（每加必抄） |
|---|---------|---------|-------------------|
| 1 | `MenuPanel/MenuTabBarView.swift:14-19` | 枚举加 case | 是（枚举本身） |
| 2 | `MenuTabBarView.swift:22-30` | `title` 穷尽 switch | **是** |
| 3 | `MenuTabBarView.swift:36-44` | `stableID` 穷尽 switch | **是**（且与 PanelTabCatalog 同源，改一处必须改两处，注释自认 :34-35） |
| 4 | `MenuTabBarView.swift:47-55` | `symbolName` 穷尽 switch | **是** |
| 5 | `NetworkMonitorUI/PanelTabCatalog.swift:15` | `stableIDs` 加 id | 是 |
| 6 | `MenuPanel/MenuPanelView+Panes.swift:35-43` | 加 `var xxxPane` | 是 |
| 7 | `MenuPanelView+Panes.swift:50-57` | `ensurePaneLoaded` 穷尽 switch | **是** |
| 8 | `MenuPanel/MenuPanelController.swift:221-259` | `configure(pane:for:)` 穷尽 switch（挂动作回调） | **是** |
| 9 | `MenuPanel/MenuPanelController+Actions.swift:106-128` | `refreshPaneFirstDisplay` 穷尽 switch（首屏补数据） | **是** |
| 10 | `MenuPanel/MenuPanelView+DataUpdates.swift` | 加一条 `updateXxx` 转发方法 | 是 |
| 11 | `Debug/MenuPanelSnapshot.swift:253-264` | `fileNameSuffix` 穷尽 switch | 是（DEBUG） |
| 12 | `Debug/MenuPanelEvidence.swift:62-72` | 环境变量 → tab 穷尽 switch | 是（DEBUG/取证） |
| 13 | `TestRunner/PanelTabCatalogTests.swift:21-26` | 硬编码「剩 5 个」「顺序 5 项」 | **是**（加 tab 必红） |
| 14 | `TestRunner/PanelTabCatalogTests.swift:47-50` | 冻结表在用 id 集合 vs stableIDs 相等 | 是 |
| — | 新建 `MenuPanel/XxxPaneView.swift` | 继承 `MenuPanelPaneView`（`MenuPanelRows.swift:321`） | — |

若新 tab 还需要新服务：再加 `AppCoordinator.swift:102 start()` 一阶段 + `MenuBarManager.swift:61-86` 构造参数 + `MenuBarManager` 传 `MenuPanelController`（:89-101）+ `MenuPanelController.swift:150-161` 构造参数 + `MenuBarManager+Sampling.swift` 采样节拍 → **再 +5 处**。

**合计：11 个文件（含新建），约 10–13 个步骤，其中 7 处是穷尽 switch 样板。** 自动覆盖的只有 `MenuPanelTab.allCases` 驱动的 11 个点（`SettingsGeneralPane+Ordering.swift:57` 排序卡、`PanelTabPreferences.swift:32-35`、`MenuPanelView+Panes.swift:87` 栈序、`MenuTabBarView.swift:86/225/228` 分段布局、两处快照遍历）。

### 1.2 场景 B：Settings 加一个分类

| # | 文件:行 | 要改什么 | 样板? |
|---|---------|---------|------|
| 1 | `Settings/SettingsSection.swift:8-19` | 枚举加 case | — |
| 2 | `SettingsSection.swift:22` `title` / `:39` `symbolName` / `:56` `fileSuffix` / `:73` `subtitle` | **4 个穷尽 switch** | **是** |
| 3 | `NetworkMonitorUI/SettingsSkeletonLogic.swift:81-93` | `SettingsSectionID` 加 case | 是（与 App 侧同名，靠 rawValue 互转兜底，`SettingsWindow+Sidebar.swift:148-155`） |
| 4 | `SettingsSkeletonLogic.swift:113-130` | `SettingsSidebarLayout.groups` 归组 | 是（但**是唯一真源**，漏写由单测判红） |
| 5 | `AppCoordinator+Settings.swift:17-76` | `factories` 字典加一条 | 是（一条 = 一个工厂闭包） |
| 6 | `TestRunner/SettingsThemeTests.swift:42-44` | 硬编码 11 | **是** |
| — | 新建 `Settings/SettingsXxxPane.swift` | 继承 `SettingsPaneView`（`SettingsPaneView.swift:12`） | — |

**合计：6 个文件（含新建），6 个步骤。** 自动覆盖：`SettingsSection.allCases` 快照遍历（`Debug/SettingsSnapshot.swift:33,166`）、侧栏构建（`SettingsWindow+Sidebar.swift:41-62`）、切页（`SettingsWindow.swift:126-152`）。

### 1.3 三个「已在往组件化走」的现状

- `PanelTabCatalog`（`NetworkMonitorUI/PanelTabCatalog.swift:12-40`）：只有**数据**（stableIDs / retiredIDs / 冻结 Int 映射），**不含** title / 图标 / 构造 / 数据依赖 → 停在「id 登记表」，不是模块声明。
- `PaneAssemblyLedger`（`NetworkMonitorUI/PaneAssemblyLedger.swift:10-36`）：泛型 `Key: Hashable` 的通用「建过没有」账本，**可复用性最高**，但调用侧装配仍是手写 switch（`MenuPanelView+Panes.swift:50-57`）。
- `SettingsSkeletonLogic`（`SettingsSkeletonLogic.swift:11-208`）：布局/分段/状态胶囊/文案截断的纯逻辑都抽走了，**但 setion→pane 的映射仍在 App 层**（`AppCoordinator+Settings.swift:17`）。
- 结论：三个文件各自解决了「表 / 记账 / 布局」中的一段，**没有任何一个把「一页 = 声明 + 构造 + 数据 + 动作」收在一起**。

## 2. 装配机制现状

### 2.1 `start()` 是手写顺序装配（14 阶段，带硬依赖注释）

`NetworkMonitor/AppCoordinator.swift:102-237`：

| 阶段 | 行 | 依赖约束（代码注释为准） |
|---|---|---|
| 1 数据库 | 103-105 | 同一实例同时满足 `DatabaseService` 与 `ClipboardRepository` |
| 2 网络监控 | 108-110 | 读 storage 的 totalRx/totalTx |
| 3 流量追踪 | 113 | 依赖 2 |
| 3b 通知与音效 | 117 | **必须早于剪贴板与额度链路**（:115-116） |
| 4 剪贴板链路 | 120 | 依赖 db + 通知 |
| 4b 截图 | 122 | — |
| 4c 系统权限 | 125 | **必须在 setupSnip 之后**（:124） |
| 5 局域网互传 | 128 | — |
| 6 额度链路 | 136-177 | provider 类型工厂 + 实例 + 注册表 + 凭据 + 提醒 + monitor，**唯一 new 具体 provider 的地方** |
| 6c 更新检查 | 179 | — |
| 6d 设置窗口 | 182 | 依赖额度 monitor |
| 6e 屏幕活动 | 189-198 | 依赖 billingMonitor（弱引用 + 强持有注释 :186-188） |
| 6f Token 统计 | 200 | 依赖 db |
| 6g 系统监控 | 202-203 | — |
| 7 MenuBarManager | 206-218 | 注入 10 个依赖 |
| 8/8b | 224/227 | 落盘定时器、自动更新 |
| 9 清理 | 232-236 | 依赖剪贴板偏好 |

**是手写顺序装配**：依赖靠代码位置与注释表达，没有任何声明式依赖描述；`stop()`（:240-261）是手写逆序，新增模块必须记得两边都加。

### 2.2 有没有「一个声明 + 自动注册」的机制？

- 面板 / 设置 / 剪贴板 / 截图 / 互传：**没有**。全仓检索 `protocol .*Module` / `struct .*Module` / `enum .*Module` → 0 命中（`grep -rn "protocol .*Module\|struct .*Module\|enum .*Module" --include=*.swift .`）。
- 唯一的注册表范式在**别的领域**，但形态正是目标的样板：
  - `BillingProviderRegistry`（`NetworkMonitorCore/Billing/BillingProvider.swift:110-150`）：`register(provider, instance:)` / `unregister` / `all`，注释明写「加 provider 类型或实例都只需注册」，组合根 `AppCoordinator.swift:151-156` 只做循环注册。
  - `SettingsWindow` 的 `factories: [SettingsSection: PaneFactory]`（`Settings/SettingsWindow.swift:23,28,42`）：**已经是「分类 → 工厂」字典注册**，只是数据源是手写字典字面量（`AppCoordinator+Settings.swift:17-76`）。
  - 通知事件：`NotificationEvent`（`NetworkMonitorCore/Notifications/NotificationEvent.swift:13`）+ `SettingsNotificationEventCard`（`Settings/SettingsNotificationEventCard.swift`），5 个功能页各传一个事件数组复用同一张卡（ProvidersPane:73 / ClipboardPane:74 / CapturePane:82 / TransferPane:47 / GeneralPane:67）。

### 2.3 懒装配怎么实现、可不可复用

- 记账：`PaneAssemblyLedger`（纯逻辑，`PaneAssemblyLedger.swift:31-35` 返回「是否首次」）+ 测试 `TestRunner/PaneAssemblyTests.swift`。
- 创建：`MenuPanelView+Panes.swift:60-65` `loadedPane<T>`（`if let existing as? T` 复用，否则 `make()` + `assemble`）。
- 入树：`Panes.swift:68-83` —— 登记 → 显隐 → 按声明序 `insertArrangedSubview`（`:86-90` 用 `MenuPanelTab.allCases` 排序）→ 宽度约束 → `layoutSubtreeIfNeeded` → 首次回调 `onPaneAssembled`。
- 回调：`MenuPanelView.swift:67-72`（`didSet` 补放已装配页，处理「回调装上之前已装配」）；`MenuPanelController.swift:214-218` `wirePaneActions` → `:221` `configure(pane:for:)`。
- 未装配页的转发：`MenuPanelView+DataUpdates.swift` 全部先取 `...IfLoaded`（`:16,23,30,37,45,60,67`），未装配直接 return。
- **可复用，但只有半泛化**：`assemble` 里 `if tab == .system { bindSystemPaneCallbacks }`（`Panes.swift:78`）是硬编码特判；`stackIndex` 绑死 `MenuPanelTab.allCases`；`loadedPane` 要求页面是 `MenuPanelPaneView` 子类（`MenuPanelRows.swift:321-326`，基类只有 `focusableRows` / `focusableCards` 两个空实现，**没有** `dataNeeds` / `firstDisplay` / `actions` 契约）。要变成通用机制，缺的是「页面自述契约」而不是账本。

## 3. UI 分层

`NetworkMonitorUI` = 61 文件纯逻辑（无 AppKit/Core 视图依赖）；视图在 App 层。分层**基本守住**：

**没有**的东西（检索为证）：
- `grep -rn "URLSession" MenuPanel Settings Clipboard Transfer Snip` → 0 命中（视图不发请求；`UpdateCheckService` 在 Settings 目录但它是服务类，由 `AppCoordinator+Settings.swift:71-74` 注入）。
- `grep -rn "DatabaseManager\|AppDatabase" MenuPanel Settings` → 0 命中（都走协议：`MenuPanelController.swift:51` `any ClipboardRepository`、`SettingsTokenController.swift:28` `any HarnessTokenRepository`）。
- `grep -rn "UserDefaults.standard" MenuPanel Settings DrawnUI` → 0 命中。

**泄漏点（2 例）**：
1. 视图直接读业务对象状态：`Settings/SettingsProvidersPane.swift:82` `monitor.registry.registrations`、`:177` `monitor.states`、`:186` `monitor.credentialStore.credentialResolution` —— 页面在 `refresh()` 里自己从 `BillingMonitor` 取 6 种状态并拼装。
2. 视图直接持有服务并触发：`MenuPanel/TokenPaneView.swift:27` `var harness`、`TokenPaneView+Interaction.swift:75` `harness.rebuildIndex(scope: .full)`、`:80` `self.update(harness.snapshot())` —— 面板页直接读快照 + 触发索引，绕过了控制器的 `updateToken` 通道。

**偏好读取**（不算违规但分散）：`Settings/SettingsCapturePane.swift:222,236,248,264` 视图直接 `storage.bool/string(forKey:)`，键常量来自 `SnipPreferenceKey`；`storage: any KeyValueStorage = AppContext.shared.storage` 作为默认参数出现 14 处（同类写法，可接受但不是构造器注入）。

**同一口径写两遍（3 例）**：
- `NetworkMonitorUI/PaneCardLayout.swift:23-28` `isCompactCell` 与 `NetworkMonitorCore/Billing/BillingLimitLayout.swift:19-21` `isCompact` 同一判据两份，注释自认「这里复制一份是因为本 target 不依赖 Core；两处取值必须一致」——现在 UI 目标确实 `import NetworkMonitorCore`（`SettingsSkeletonLogic.swift:2`），这条理由已过期。
- `MenuPanel/MenuPanelView.swift:185-191` 手写 `10 + 28 + 12 + pane + 12` 高度公式，而 `NetworkMonitorUI/PaneHeightBudget.swift:9-40` 同一条预算**全仓只有 TestRunner 引用**（`grep -rn PaneHeightBudget NetworkMonitor` → 0 命中）→ 纯逻辑写了但没接进真实布局。
- 卡片底绘制两份：`Appearance/ThemeStyle.swift:115-140` `drawCard` 与 `Settings/SettingsTheme.swift:209-233` `drawCardBackground`（差异只有 `cardFillAlpha`，注释自认）。

## 4. 视图基类与可组合性

**共用骨架覆盖（5 页满覆盖）**：
- `PaneHeaderRowView`（`MenuPanel/PaneChromeViews.swift:15`）：network:59 / billing:26 / token:68 / system:77 / transfer:34 —— 5/5 页都用。
- `PaneStateBandView`（`MenuPanel/PaneStateBandView.swift:15`，外壳 `PaneBandChrome`）：network:61 / billing:30 / token:83-85（三条）/ transfer:36 —— 4 页 6 个实例。
- `PaneCardStyle`（`MenuPanel/PaneCardStyle.swift:19`）：几何/字号的唯一真源；`TokenPaneStyle`（:1-40）与 `BillingPaneStyle`（:1-30）已降级为纯转发，`MenuPanelStyle`（:27-48）部分转发 —— 收敛得不错。

**没接入共用骨架 / 各画一遍的**：
- `MenuPanel/SystemStateBandView.swift:20`：系统页自带一条（已复用 `PaneBandChrome` 外壳，但条目布局自写）。
- `MenuPanel/SystemDetailPaneView.swift:59-87`：二级页自建 backBar + crumb（不用 `PaneHeaderRowView`）。
- `MenuPanel/TokenDetailPages.swift:63-102`：二级页自建 `TokenDetailBackButton` + 行（同上）。
- `Clipboard/ClipboardHeadBand.swift:32-39`、`ClipboardCardFooterBand.swift:22`：剪贴板面板头/底各自 `NSBezierPath(roundedRect:)` 自绘，不走 `PaneBandChrome`。
- `Snip/*`：工具条与二级面板完全独立（0 处 `PaneCardStyle`/`PaneBandChrome`）。

**同一形态的实现份数**：
| 形态 | 份数 | 位置 |
|---|---|---|
| 卡片底绘制函数 | **3** | `DrawnUI/DrawnCardSurface.swift:16`、`Appearance/ThemeStyle.swift:115`、`Settings/SettingsTheme.swift:209` |
| 卡片承载类 | **7** | `MenuPanelCardView`(MenuPanelRows.swift:240)、`PaneCardBackgroundView`(:12)、`SystemCardView`(:16，5 个具体卡继承它)、`SystemDetailCardView`(SystemDetailComponents.swift:9)、`TokenCardRow`/TokenFamilyCardView(TokenPaneCards.swift:10/157)、`SettingsCardView`(SettingsComponents.swift:48)、`DrawnCard`(DrawnUI/DrawnCard.swift:14，仅 DEBUG probe 用) |
| 状态带 | **2 类 + 1 外壳** | `PaneStateBandView`、`SystemStateBandView`、`PaneBandChrome` |
| 行视图 | **13 个类** | `MenuPanelRow`(:9) 基类 + Token 3 种 + BillingAxisRow + TokenAxisRowView + TokenLegendRowView + SettingsRowView + ProviderRowView + Clipboard 2 种 …；而「一行 = 零视图」的 `DrawnRowList` 只用了 **3 处**（`NetworkPaneView.swift:39`、`SystemProcessListView`、`TokenScreenContent+Ranking`） |

即：**抽屉里已经有 `DrawnRowList`/`DrawnCardSurface`/`PaneBandChrome`，但 60% 的页面还在建 NSView 行**。

## 5. 状态与数据流

获取路径共 4 类，**没有统一方向**：

1. **服务回调赋值（推）**：`MenuPanelController+DataSources.swift:15-19` `billingMonitor.onUpdate = { ... }` → `content.updateBilling(...)`；`TransferController.attach(panel:)`（`Transfer/TransferController.swift:55`）+ `transfer.isPanelVisible` 闭包（`MenuPanelController.swift:228`）。
2. **AppEvents 观察（推）**：`MenuPanelController+DataSources.swift:25`（`harnessUsageChanged`）、`:40`（`numberUnitStyleChanged`）、`+Appearance.swift:17,22`（`appearanceChanged`/`renderTierChanged`）、`MenuPanelView+TabPreferences.swift:16`（`panelTabsChanged`）、`SettingsWindow.swift:162,166`（外观/渲染档）。事件定义集中在 `NetworkMonitorCore/Infrastructure/AppEvents.swift`。
3. **定时 tick 拉（拉）**：`MenuPanelController+Open.swift:87-105`（1s 速率）、`:168-175`（5s 流量/进程）、`+SystemMetrics.swift:18-40`、`MenuBarManager+Sampling.swift:27-42`（可见性降频）。
4. **视图自己拉（旁路）**：`SettingsProvidersPane.swift:174-203`（`refresh()` 里读 monitor 6 种状态）、`TokenPaneView+Interaction.swift:75-80`（视图触发 rebuildIndex 并自读快照）、`SettingsCapturePane.swift:222-264`（视图直读 storage）。

**绕过统一通道的视图**：`TokenPaneView`（自持服务 + 自读快照，且 `harness` 是可变属性，由 `MenuPanelController.swift:249` 后赋值注入——装配时序耦合）、`SettingsProvidersPane`（把 monitor 当数据源直读）、`SystemStateBandView`（自己从 `SystemMetricsSnapshot` 取字段，没有「页 → 快照」契约）。

**方向性问题**：推路径是「服务 → 控制器 → 每页显式 `updateXxx`」（`MenuPanelView+DataUpdates.swift` 7 个方法），每加一页就要在控制器加分支（`MenuPanelController+Actions.swift:106-128` 的 switch、`MenuPanelController.swift:221` 的 switch）；拉路径是「页自己 refresh()」。两类路径的判据不统一。

## 6. 结论：目标形态可行性

**可行，且不需要新框架**——现有代码已把三类零件备齐：注册表（`BillingProviderRegistry`）、声明表（`PanelTabCatalog`/`SettingsSidebarLayout`）、懒装配账本（`PaneAssemblyLedger`）。缺的是把它们**合成一个页级契约**。

### 需要新增的抽象（3 个，均可放 `NetworkMonitorUI`，纯值 + 闭包工厂由 App 注入）

1. `PaneModuleDescriptor`（值类型）：`id / title / symbol / sortKey / snapshotSuffix / evidenceKey` + 一组能力声明：`makePane: () -> MenuPanelPaneView`、`firstDisplay: (MenuPanelController) -> Void`、`bindActions: (MenuPanelPaneView, MenuPanelController) -> Void`、`applySnapshot: (MenuPanelPaneView, PaneSnapshot) -> Void`、`dataNeeds: Set<PaneDataNeed>`。
2. `PaneModuleRegistry`：`register(_ descriptor)` / `all: [Descriptor]` / `descriptor(for:)`，取代 `MenuTabBarView` 的 3 个 switch + `ensurePaneLoaded` + `configure` + `refreshPaneFirstDisplay` + `fileNameSuffix` + `tab(for:)` 共 7 处。
3. `SettingsModuleDescriptor`：同构（`id / title / symbol / subtitle / fileSuffix / makePane`），取代 `SettingsSection` 的 4 个 switch 并把 `AppCoordinator+Settings.swift:17-76` 的字典字面量变成注册循环。

### 现有雏形（可直接改造，不必重写）

| 雏形 | file:line | 用途 |
|---|---|---|
| `PanelTabCatalog` | `NetworkMonitorUI/PanelTabCatalog.swift:12` | 稳定 id / 冻结迁移表 → 直接成为 descriptor 的 id 真源 |
| `PaneAssemblyLedger` | `NetworkMonitorUI/PaneAssemblyLedger.swift:10` | 懒装配判据，泛型已通用 |
| `PaneAssembly` 实现 | `MenuPanel/MenuPanelView+Panes.swift:60-90` | 装配动作（入栈/约束/首次回调）已成代码，只需把 `switch` 换成查表 |
| `SettingsSidebarLayout` | `SettingsSkeletonLogic.swift:113-130` | 唯一分组真源 |
| `SettingsWindow.factories` | `Settings/SettingsWindow.swift:23,28,42` + `AppCoordinator+Settings.swift:17` | 「分类 → 工厂」字典注册，最接近目标 |
| `BillingProviderRegistry` | `NetworkMonitorCore/Billing/BillingProvider.swift:110-150` | 「一个声明 + register」的**范式样板**（含唯一性、替换、注销语义） |
| `SettingsNotificationEventCard` | `Settings/SettingsNotificationEventCard.swift` + `NotificationEvent.swift:13` | 「事件声明 + 每页复用一行」的**组件化样板** |
| `MenuPanelPaneView` 基类 | `MenuPanel/MenuPanelRows.swift:321-326` | 已有页面基类，只需扩成契约（当前只有 2 个空属性） |

### 迁移顺序（低风险 → 高），影响面

1. **只加不改行为**：把 `MenuPanelTab` 的 title/stableID/symbol 三个 switch 搬进 `PaneModuleDescriptor`，建 `PaneModuleRegistry`，`MenuTabBarView` 改为查表。影响 2 文件 + 1 新文件；行为等价可用现快照对比（`NM_DRAWN_PROBE`/`MenuPanelSnapshot`）。
2. **吃掉懒装配 switch**：`MenuPanelView+Panes.swift:50-57` 的 `ensurePaneLoaded` + `:35-43` 的 5 个属性改为 `registry.descriptor(for: tab)?.makePane()`；顺带把 `:78` 的 system 特判改成 `descriptor.onFirstAssemble`。影响 1 文件。
3. **吃掉动作/首屏 switch**：`MenuPanelController.swift:221` 与 `+Actions.swift:106` 改为 `descriptor.bindActions` / `descriptor.firstDisplay`。影响 2 文件。
4. **吃掉数据转发**：`MenuPanelView+DataUpdates.swift` 7 个方法 → `descriptor.applySnapshot`，控制器 tick 里按 `dataNeeds` 分发。影响 2 文件（含控制器 tick）。
5. **设置页同构**：`SettingsSection` 4 个 switch + factories 字典 → `SettingsModuleDescriptor` 注册循环。影响 3 文件 + 2 处测试硬编码。
6. **收口卡片/状态带**：`SettingsTheme.drawCardBackground` 合并进 `ThemeStyle.drawCard`（加 `fillAlpha` 参数）；`DrawnCardSurface` 定为唯一卡底原语；`PaneHeightBudget` 接回 `MenuPanelView.desiredContentHeight`。影响 3 文件。
7. **测试与取证**：`PanelTabCatalogTests.swift:21-26,47-50`、`SettingsThemeTests.swift:42-44` 从硬编码数量改为「注册表自洽」断言（`registry.all.count == catalog.stableIDs.count`），这样以后加 tab 不再必红。

### 风险 / 影响面

- 硬编码断言是迁移过程中最先红的：`PanelTabCatalogTests.swift:21,24-26,47-50`（5 处）、`SettingsThemeTests.swift:42-43`（2 处）。
- 取证链路按中文名找 tab：`nmcli/Scenario.swift:79` `PanelGeometry.visibleTabIndex(of: "系统")` —— 改 title 会打断自动化验收。
- `Debug/MenuPanelEvidence.swift:62` 的环境变量映射是第二份「id → tab」，与 `PanelTabCatalog` 不同源。
- `TokenPaneView.harness` 是装配后回填的可变属性（`MenuPanelController.swift:249`），改注册表时必须把它并进 `bindActions`，否则顺序依赖会静默失效。

---

## 未覆盖项

- 未运行构建 / 测试（按派发约束），所有结论来自静态检索与阅读。
- `nmcli`、`TestRunner` 只做了引用检索，未逐行读完。
- `Clipboard/`（56 文件）与 `Snip/`（32 文件）只核了「是否接入共用骨架 / 是否有违规数据访问」，未做同深度的接线成本核算。
- 未评估 Billing / Token / System 三页内部（子卡片、二级详情）的组件复用度，只统计了页级骨架。
