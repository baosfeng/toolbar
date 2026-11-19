import AppKit
import NetworkMonitorUI

// MARK: - 面板分页装配件（Descriptor + 闭包，App target）

/// 一个面板分页的**装配件** —— 描述符（可测纯值）+ 造页 / 挂动作 / 首屏数据三个闭包
///
/// 与 `PaneModuleDescriptor` 的分工（架构契约 §1）：描述符进 UI 库供 TestRunner 断言，
/// 带 AppKit 类型与闭包的部分只能留在 App target，否则 UI 库再也不能被 TestRunner 依赖。
///
/// 取代改造前的四处穷尽 switch：`MenuPanelView.ensurePaneLoaded`、
/// `MenuPanelController.configure(pane:for:)`、`+Actions.refreshPaneFirstDisplay`、
/// 以及分段条的 title / stableID / symbol 三处（那三处改由描述符目录提供）。
@MainActor
struct PaneModule {

    /// 纯值描述符（id / 标题 / 图标 / 快照后缀 / 取证标识 / 声明序）
    let descriptor: PaneModuleDescriptor

    /// 造页 —— 只在首次装配该页时调用一次
    let makePane: () -> MenuPanelPaneView

    /// 挂动作回调 —— 该页首次装配时调用一次（替代 `configure(pane:for:)` 的穷尽 switch）
    let configure: (MenuPanelController, MenuPanelPaneView) -> Void

    /// 首屏补数据 —— 该页首次被切到时调用一次（替代 `refreshPaneFirstDisplay` 的穷尽 switch）
    let firstDisplay: (MenuPanelController, MenuPanelPaneView) -> Void

    init(descriptor: PaneModuleDescriptor,
         makePane: @escaping () -> MenuPanelPaneView,
         configure: @escaping (MenuPanelController, MenuPanelPaneView) -> Void = { _, _ in },
         firstDisplay: @escaping (MenuPanelController, MenuPanelPaneView) -> Void = { _, _ in }) {
        self.descriptor = descriptor
        self.makePane = makePane
        self.configure = configure
        self.firstDisplay = firstDisplay
    }

    /// 该分页的历史编号（= `MenuPanelTab.rawValue`，偏好迁移按它对齐）
    var rawValue: Int { descriptor.rawValue }
}

// MARK: - 分页装配注册表

/// 分页装配注册表 —— 组合根一次注册，分段条 / 懒装配 / 动作 / 首屏 / 快照 / 取证全部从这里读
///
/// 新增一个分页 = 新建 Pane 文件 + 在 `standard()` 里 `register` 一行；
/// 不再有「改一处必须改四处」的穷尽 switch。注册顺序由 `descriptor.sortIndex` 决定，
/// 与 `PanelTabCatalog.stableIDs` 同序（自洽性由 TestRunner 断言）。
@MainActor
final class PaneModuleRegistry {

    private var storage: [String: PaneModule] = [:]
    private var descriptors = PaneDescriptorRegistry()

    /// 空注册表（测试 / 未装配场景）
    init() {}

    /// 注册一个分页装配件；同 id 重复注册 = 替换（沿用 `BillingProviderRegistry` 语义）
    @discardableResult
    func register(_ module: PaneModule) -> Bool {
        let isNew = storage[module.descriptor.id] == nil
        storage[module.descriptor.id] = module
        descriptors.register(module.descriptor)
        return isNew
    }

    /// 全部装配件（按描述符声明序）
    var all: [PaneModule] {
        descriptors.all.compactMap { storage[$0.id] }
    }

    /// 按稳定 id 查装配件
    func module(forID id: String) -> PaneModule? { storage[id] }

    /// 按分页枚举查装配件（历史编号对齐描述符，rawValue 冻结不会错位）
    func module(for tab: MenuPanelTab) -> PaneModule? {
        guard let descriptor = PaneModuleCatalog.descriptor(forRawValue: tab.rawValue) else { return nil }
        return storage[descriptor.id]
    }

    /// 注册表自洽判据（空数组 = 自洽）
    func validate() -> [PaneModuleProblem] { descriptors.validate() }

    /// 全部描述符（分段条 / 快照 / 取证按它渲染）
    var allDescriptors: [PaneModuleDescriptor] { descriptors.all }

    /// 按取证标识查描述符（`NM_EVIDENCE_TAB`）
    func descriptor(forEvidenceKey key: String) -> PaneModuleDescriptor? {
        descriptors.descriptor(forEvidenceKey: key)
    }
}

// MARK: - 五个分页的装配声明（组合根唯一的注册处）

extension PaneModuleRegistry {

    /// 标准装配：五个分页各一条声明 —— 内容与改造前的穷尽 switch 逐项等价
    ///
    /// 建页闭包不捕获控制器：动作与首屏回调都以参数形式拿到 controller，
    /// 否则 `AppCoordinator → 面板 → 注册表 → 控制器` 会成环。
    static func standard() -> PaneModuleRegistry {
        let registry = PaneModuleRegistry()
        for descriptor in PaneModuleCatalog.descriptors {
            guard let module = makeModule(for: descriptor) else { continue }
            registry.register(module)
        }
        // 开发期自证：目录里的分页必须都有装配件（漏一条就少一页，且不会有编译错误）
        let problems = registry.validate()
        assert(problems.isEmpty, "分页装配注册表与目录不自洽：\(problems.map(\.description))")
        return registry
    }

    /// 描述符 → 装配件（按稳定 id 分派，新增分页只加一条分支，不改已有任何一条）
    ///
    /// 这一层保留按 id 的映射是必要的：各页造页闭包的返回类型互不相同
    /// （`NetworkPaneView` / `TransferPaneView` …），只有这里能把具体类型收口成
    /// `MenuPanelPaneView`。未登记的 id 在开发期 `assertionFailure`、release 下跳过装配。
    private static func makeModule(for descriptor: PaneModuleDescriptor) -> PaneModule? {
        switch descriptor.id {
        case "network":
            return PaneModule(descriptor: descriptor,
                              makePane: { NetworkPaneView() },
                              firstDisplay: { controller, _ in
                                  // 补的是 5 秒档的流量 / 柱图 / 进程，以及与系统页同源的 Wi-Fi 链路条；
                                  // 速率与折线本来由 1 秒 tick 每秒推，这里顺手补一帧避免首屏「0 B/s」
                                  controller.refreshMidFrequency()
                                  controller.content.updateSpeeds(
                                      down: max(controller.monitor.downloadSpeed, 0),
                                      up: max(controller.monitor.uploadSpeed, 0),
                                      downHistory: controller.downHistory,
                                      upHistory: controller.upHistory)
                                  controller.content.updateWiFiLink(controller.systemMonitor?.snapshot?.wifi)
                              })
        case "transfer":
            return PaneModule(descriptor: descriptor,
                              makePane: { TransferPaneView() },
                              configure: { controller, pane in
                                  guard let transfer = pane as? TransferPaneView else { return }
                                  // 传送页的「是否可见」由这里注入：收起时它只更新模型、不推视图
                                  // （见 TransferController.render）；attach 内部会 render 一次，
                                  // 把当前设备 / 会话状态推进这个刚装配出来的面板
                                  transfer.isPanelVisible = { [weak controller] in
                                      controller?.popover.isShown ?? false
                                  }
                                  controller.transferController?.attach(panel: transfer)
                              },
                              firstDisplay: { controller, _ in
                                  // attach 时已渲染一次，这里强制补推一次（收起期间的数据变化不能漏）
                                  controller.transferController?.refreshNow()
                              })
        case "credits":
            return PaneModule(descriptor: descriptor,
                              makePane: { BillingPaneView() },
                              configure: { controller, pane in
                                  guard let billing = pane as? BillingPaneView else { return }
                                  billing.onRefresh = { [weak controller] in
                                      controller?.billingMonitor?.refresh(force: true)
                                  }
                                  billing.onRetry = { [weak controller] in
                                      controller?.billingMonitor?.refresh(force: true)
                                  }
                                  billing.onRangeChange = { [weak controller] range, providerID in
                                      controller?.billingMonitor?.selectRange(range, providerID: providerID)
                                  }
                                  // 未配置块「去设置配置」：打开统一设置窗口并落到额度 Provider 页
                                  billing.onOpenSettings = { [weak controller] in
                                      controller?.requestSettings(section: .providers)
                                  }
                                  // 展开 / 收起改变内容高度：通知面板重算 popover 尺寸
                                  billing.onContentChanged = { [weak controller] in
                                      guard let controller else { return }
                                      controller.content.delegate?
                                          .menuPanelViewDidChangeContent(controller.content)
                                  }
                              },
                              firstDisplay: { controller, _ in
                                  controller.renderBillingSnapshot()
                              })
        case "token":
            return PaneModule(descriptor: descriptor,
                              makePane: { TokenPaneView() },
                              configure: { controller, pane in
                                  guard let token = pane as? TokenPaneView else { return }
                                  // 页头刷新＝一键重扫（清空索引 + 全量重建），由页面自己持有服务并回执
                                  token.harness = controller.harnessUsage
                                  token.onRefresh = { [weak controller] in
                                      controller?.content.tokenPaneIfLoaded?.rebuildIndex()
                                  }
                                  token.onOpenSettings = { [weak controller] section in
                                      controller?.requestSettings(section: section)
                                  }
                                  token.onContentChanged = { [weak controller] in
                                      guard let controller else { return }
                                      controller.content.delegate?
                                          .menuPanelViewDidChangeContent(controller.content)
                                  }
                              },
                              firstDisplay: { controller, _ in
                                  controller.refreshToken()
                              })
        case "system":
            // 网络页与系统页没有面板内动作回调（系统页回调由面板自己在装配时挂）；
            // 系统页首屏由 didSelectTab 里的 poll + refreshSystem 补齐（每次切到都会走）
            return PaneModule(descriptor: descriptor,
                              makePane: { SystemPaneView() })
        default:
            // 描述符目录新增了 id 却没有装配件：开发期立刻暴露，release 下该页不装配（不崩）
            assertionFailure("分页 \(descriptor.id) 缺少装配件声明")
            return nil
        }
    }
}
