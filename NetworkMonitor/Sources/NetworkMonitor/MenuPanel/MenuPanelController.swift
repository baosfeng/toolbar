import AppKit
import NetworkMonitorCore
import NetworkMonitorDesign
import NetworkMonitorFeatureBilling
import NetworkMonitorUI

// MARK: - 面板内容控制器

/// 面板内容视图控制器 — NSPopover 需要一个 NSViewController 承载根视图
private final class MenuPanelContentViewController: NSViewController {
    private let panelView: MenuPanelView

    init(panelView: MenuPanelView) {
        self.panelView = panelView
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        view = panelView
    }
}

// MARK: - 菜单面板控制器

/// 菜单栏下拉面板控制器 — NSPopover 生命周期、刷新策略与动作执行
///
/// 刷新分层（与状态栏共用同一个 1 秒定时器）：
/// - 1 秒：实时速率（大数字 + 折线）
/// - 5 秒：今日流量、近 6 日柱状图、活跃进程、IP / Wi-Fi / 开机自启动
/// - 面板打开时：强制全量刷新一次
@MainActor
final class MenuPanelController: NSObject, NSPopoverDelegate {

    // MARK: 依赖

    // `content` / `paster` / `transferController` / `billingMonitor` / `storage` / `logger`
    // 由 `private` 放宽为 `internal`：拆出的 `MenuPanelController+Actions.swift` 跨文件访问，
    // 同模块内无其他调用方。

    // popover 放宽为 internal：数据绑定扩展（MenuPanelController+DataSources）要读 isShown
    let popover = NSPopover()
    /// 面板根视图（用注入存储构造：分页偏好必须与设置页读写同一份存储）
    let content: MenuPanelView
    // 以下三个监控服务由 private 放宽为 internal：刷新链路已拆到
    // MenuPanelController+Refresh.swift（速率、流量、进程采样），同模块内无其他调用方。
    let monitor: any NetworkMonitoringService
    let processMonitor: any ProcessNetworkMonitoringService
    let trafficTracker: any TrafficTrackingService
    // 放宽为 internal：数据源绑定扩展（+DataSources）的剪贴板刷新要读
    let repository: any ClipboardRepository
    let paster: ClipboardPaster
    let transferController: TransferController?
    /// 额度页状态管理器（nil = 未装配计费链路）
    let billingMonitor: BillingMonitor?
    /// Token 页数据服务（nil = 未装配 DSH 索引链路）
    let harnessUsage: (any HarnessUsageServicing)?
    /// 系统指标采样服务（nil = 未装配系统监控链路）
    // 放宽为 internal：系统页刷新扩展（MenuPanelController+SystemMetrics）要读
    let systemMonitor: (any SystemMonitoringService)?
    /// 系统监控偏好（采样周期 / 面板显示项）
    let systemPreferences: SystemMonitorPreferences?
    /// 系统指标历史（60 点环形缓冲，1 秒采样）
    // 不使用 private(set)：系统页刷新扩展跨文件 append
    var systemHistory = SystemMetricsHistory()
    /// 上次系统页视图刷新时间（扩展里读写，故为 internal）
    var lastSystemRefresh: Date = .distantPast
    let storage: any KeyValueStorage
    let logger: LoggingService
    /// 开机自启动开关（与设置页共用同一份 SMAppService 逻辑）
    let launchAtStartupService = LaunchAtStartupService()

    /// 面板数据读取队列（剪贴板 / Token 快照）
    ///
    /// 并发而非串行：两页各自独立，一页的重活（Token 聚合补算）不该把另一页的首屏拖住；
    /// 「只渲染最新一次结果」由 LatestRequestGate 保证，不依赖队列顺序。
    let dataReadQueue = DispatchQueue(label: "com.bsfeng.yilan.panelDataRead",
                                     qos: .userInitiated, attributes: .concurrent)
    /// 剪贴板刷新请求闸门（异步读 + 只接受最新一次结果）
    var clipboardRequests = LatestRequestGate()
    /// Token 快照刷新请求闸门（同上）
    var tokenRequests = LatestRequestGate()
    /// 主线程看门狗（心跳打点见 tick 与 sendEvent 路径）
    let watchdog = MainThreadWatchdog()

    // MARK: 回调（组合根注入）

    /// 打开完整剪贴板历史面板
    var onOpenClipboardHistory: (() -> Void)?
    /// 打开统一设置窗口（参数 nil = 默认页）
    var onOpenSettings: ((SettingsSection?) -> Void)?

    // MARK: 状态

    // 以下四项由 private 放宽为 internal：刷新链路已拆到
    // MenuPanelController+Refresh.swift（采样折线、中频节流），同模块内无其他调用方。

    /// 折线采样（60 个 1 秒点）
    var downHistory: [Double] = []
    var upHistory: [Double] = []
    // 两个节流参数改为**实例可变**：渲染帧率档切换要重写它们。
    // 原先是 static let，切档后永远停在默认值——「设置页切了但没生效」的典型成因。
    /// 折线采样点上限（1 点 = 1 个 tick），默认取标准档
    var maxHistory: Int = RenderTierLogic.standard.historyPoints
    /// 中频刷新间隔（秒）——直接读当前档位，不另存一份实例状态
    ///
    /// 原先存成实例变量、由 `applyRenderTier` 改写：多一份状态就多一次「切了档但没写进去」
    /// 的分叉机会（`PanelRefreshPolicy` 与取证都读档位，两处永远同一口径）。
    var midInterval: TimeInterval { RenderTierLogic.profile(for: currentRenderTier).midInterval }
    /// 当前渲染档位（切档后由 `applyRenderTier` 更新，tick 据此判定是否停摆）
    var currentRenderTier: RenderTier = .standard
    var lastMidRefresh: Date = .distantPast
#if DEBUG
    /// 取证专用（仅 DEBUG）：强制进程/剪贴板空态，用于核对空态字号
    var forceEmptyDataForEvidence = false
#endif
    /// 最近一次收起时间 — 用于吞掉「点击状态栏按钮先触发 transient 收起、再触发按钮动作」的重复开合
    // 放宽为 internal：toggle / popoverDidClose 已拆到 MenuPanelController+Open.swift
    var lastCloseDate: Date = .distantPast
    /// 内容更新批处理深度（> 0 时尺寸重算只记账、不布局）
    // 放宽为 internal：批处理开合在 MenuPanelController+Refresh.swift，判定在 PanelContentSizing
    var contentBatchDepth = 0
    /// 批处理期间是否收到过强制尺寸重算请求
    var contentBatchNeedsForceSize = false
    /// 上次内容高度的轻量签名（分页 + 当前页可交互行数）：相同则跳过整树布局
    var lastContentSizeSignature = ""
    /// 上次真正算过高度的时间（合并节流用）
    var lastContentSizeCheck: Date = .distantPast
    /// 节流窗口内到达的多次请求合并成的一次补算任务
    var pendingContentSizeTask: DispatchWorkItem?
    /// 额度推送是否正在处理中（重入保护）
    ///
    /// 额度刷新是推送式：`refresh()` → `emit()` → 面板 `updateBilling` → 面板通知
    /// `menuPanelViewDidChangeContent`，而后者在额度页又会回头调 `refresh()`。
    /// 空态下每轮都 emit 时这条反馈边会同步无限递归（栈写爆 → SIGSEGV）。
    /// 置位期间收到的「内容变更」不再回拉，见 `BillingRefreshGate`。
    var billingPushInFlight = false
    /// 是否已做过启动预热（只做一次）
    // 放宽为 internal：预热逻辑在 MenuPanelController+Open.swift（显示 / 收起同文件）
    var hasPrewarmed = false
    // 放宽为 internal：数据源绑定扩展（+DataSources）负责注册 / 读取
    // 放宽为 internal：数据绑定扩展要注册 / 移除
    nonisolated(unsafe) var harnessObserver: NSObjectProtocol?
    // 放宽为 internal：数据绑定扩展要注册 / 移除
    // 放宽为 internal：数据绑定扩展要注册 / 移除
    nonisolated(unsafe) var unitObserver: NSObjectProtocol?
    // 放宽为 internal：外观绑定扩展（+Appearance）要注册 / 移除
    nonisolated(unsafe) var appearanceObserver: NSObjectProtocol?
    nonisolated(unsafe) var renderTierObserver: NSObjectProtocol?

    // MARK: - 初始化

    init(networkMonitor: any NetworkMonitoringService,
         processMonitor: any ProcessNetworkMonitoringService,
         trafficTracker: any TrafficTrackingService,
         repository: any ClipboardRepository,
         paster: ClipboardPaster,
         transferController: TransferController? = nil,
         billingMonitor: BillingMonitor? = nil,
         harnessUsage: (any HarnessUsageServicing)? = nil,
         systemMonitor: (any SystemMonitoringService)? = nil,
         systemPreferences: SystemMonitorPreferences? = nil,
         storage: any KeyValueStorage = AppContext.shared.storage,
         logger: LoggingService = AppContext.shared.logger) {
        self.monitor = networkMonitor
        self.processMonitor = processMonitor
        self.trafficTracker = trafficTracker
        self.repository = repository
        self.paster = paster
        self.transferController = transferController
        self.billingMonitor = billingMonitor
        self.harnessUsage = harnessUsage
        self.systemMonitor = systemMonitor
        self.systemPreferences = systemPreferences
        self.storage = storage
        self.content = MenuPanelView(storage: storage)
        self.logger = logger
        super.init()

        configurePopover()
        // 主线程看门狗：启动即开始看护（心跳在 tick 与 sendEvent 路径打）
        watchdog.start()
        // 分页动作在「该页首次装配」时才挂：懒装配下这里直接读 pane 属性会把全部分页提前建出来
        wirePaneActions()
        bindBilling()
        bindHarnessUsage()
        bindNumberUnitStyle()
        bindAppearance()
        applyRenderTier(AppearancePreferences(storage: storage).renderTier)
    }

    nonisolated deinit {
        if let harnessObserver {
            NotificationCenter.default.removeObserver(harnessObserver)
        }
        if let unitObserver {
            NotificationCenter.default.removeObserver(unitObserver)
        }
        if let appearanceObserver {
            NotificationCenter.default.removeObserver(appearanceObserver)
        }
        if let renderTierObserver {
            NotificationCenter.default.removeObserver(renderTierObserver)
        }
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = MenuPanelContentViewController(panelView: content)
        popover.contentSize = NSSize(width: MenuPanelStyle.panelWidth, height: 320)
        popover.delegate = self
        content.delegate = self
    }

    /// 分页动作装配入口（懒装配：动作挂在「该页首次装配」这一刻，不提前建页）
    ///
    /// 具体挂什么由注册表里该分页的 `configure` 闭包声明（`MenuPanel/PaneModule.swift`）：
    /// 加一个分页只加一份声明，这里不再有穷尽 switch。
    private func wirePaneActions() {
        content.onPaneAssembled = { [weak self] tab, pane in
            guard let self, let module = content.paneModules.module(for: tab) else { return }
            module.configure(self, pane)
        }
    }
}