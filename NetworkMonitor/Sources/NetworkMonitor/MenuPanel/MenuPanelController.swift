import AppKit
import NetworkMonitorCore

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
/// - 事件驱动：剪贴板条目（`AppEvents.clipboardChanged`）
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
    // 以下三个监控服务由 private 放宽为 internal：打开 / 刷新链路已拆到
    // MenuPanelController+Open.swift（速率、流量、进程采样），同模块内无其他调用方。
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

    // MARK: 回调（组合根注入）

    /// 打开完整剪贴板历史面板
    var onOpenClipboardHistory: (() -> Void)?
    /// 打开统一设置窗口（参数 nil = 默认页）
    var onOpenSettings: ((SettingsSection?) -> Void)?

    // MARK: 状态

    // 以下四项由 private 放宽为 internal：打开 / 刷新链路已拆到
    // MenuPanelController+Open.swift（采样折线、中频节流），同模块内无其他调用方。

    /// 折线采样（60 个 1 秒点）
    var downHistory: [Double] = []
    var upHistory: [Double] = []
    // 两个节流参数改为**实例可变**：渲染帧率档切换要重写它们。
    // 原先是 static let，切档后永远停在默认值——「设置页切了但没生效」的典型成因。
    /// 折线采样点上限（1 点 = 1 个 tick），默认取标准档
    var maxHistory: Int = RenderTierLogic.standard.historyPoints
    /// 中频刷新间隔，默认取标准档
    var midInterval: TimeInterval = RenderTierLogic.standard.midInterval
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
    // 放宽为 internal：批处理开合与判定都在 MenuPanelController+Open.swift
    var contentBatchDepth = 0
    /// 批处理期间是否收到过强制尺寸重算请求
    var contentBatchNeedsForceSize = false
    /// 是否已做过启动预热（只做一次）
    // 放宽为 internal：预热逻辑在 MenuPanelController+Open.swift
    var hasPrewarmed = false
    // 放宽为 internal：数据源绑定扩展（+DataSources）负责注册 / 读取
    nonisolated(unsafe) var clipboardObserver: NSObjectProtocol?
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
        transferController?.attach(panel: content.transferPane)
        wireActions()
        observeClipboardChanges()
        bindBilling()
        bindHarnessUsage()
        bindNumberUnitStyle()
        bindAppearance()
        applyRenderTier(AppearancePreferences(storage: storage).renderTier)
    }

    nonisolated deinit {
        if let clipboardObserver {
            NotificationCenter.default.removeObserver(clipboardObserver)
        }
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

    /// 面板内动作装配（点击条目粘贴、设置入口、自启动切换、退出）
    private func wireActions() {
        content.clipboardPane.onSelectItem = { [weak self] item in self?.paste(item) }
        content.clipboardPane.onRequestSettings = { [weak self] in self?.requestSettings(section: .clipboard) }
        content.clipboardPane.onRequestHistory = { [weak self] in self?.requestClipboardHistory() }
        content.billingPane.onRefresh = { [weak self] in self?.billingMonitor?.refresh(force: true) }
        content.billingPane.onRetry = { [weak self] in self?.billingMonitor?.refresh(force: true) }
        content.billingPane.onRangeChange = { [weak self] range, providerID in
            self?.billingMonitor?.selectRange(range, providerID: providerID)
        }
        // 未配置块「去设置配置」：打开统一设置窗口并落到额度 Provider 页
        content.billingPane.onOpenSettings = { [weak self] in
            self?.requestSettings(section: .providers)
        }
        content.tokenPane.onRefresh = { [weak self] in self?.rebuildTokenIndex() }
        content.tokenPane.onContentChanged = { [weak self] in
            guard let self else { return }
            self.content.delegate?.menuPanelViewDidChangeContent(self.content)
        }
        // 展开 / 收起改变内容高度：通知面板重算 popover 尺寸
        content.billingPane.onContentChanged = { [weak self] in
            guard let self else { return }
            self.content.delegate?.menuPanelViewDidChangeContent(self.content)
        }
    }
}
