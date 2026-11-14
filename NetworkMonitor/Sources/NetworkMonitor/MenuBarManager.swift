import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - Menu Bar Manager

/// 菜单栏 UI 总控制器 — 状态栏网速显示 + 下拉面板生命周期
///
/// 状态栏只显示 ↑↓ 网速（`StatusBarView`）；点击按钮展开 `MenuPanelController` 的
/// NSPopover 自定义面板（网络 / 剪贴板 / 传送 / 额度 / Token / 系统六页），不再使用 NSMenu。
@MainActor
final class MenuBarManager: NSObject {

    // 放宽为 internal：DEBUG 取证扩展（MenuBarManager+Evidence）要读状态栏按钮文本
    let statusItem: NSStatusItem
    /// 放宽为 internal：状态栏文本组装拆在 MenuBarManager+StatusTitle.swift
    let monitor: any NetworkMonitoringService
    private let processMonitor: any ProcessNetworkMonitoringService
    private let trafficTracker: any TrafficTrackingService
    // 放宽为 internal：DEBUG 取证与测量扩展要直接驱动面板
    let panel: MenuPanelController
    // 放宽为 internal：显示偏好扩展（+DisplayPreferences）切档后要打生效日志
    let logger: LoggingService
    /// 系统指标采样服务（nil = 未装配；采样频率跟随偏好周期）
    private let systemMonitor: (any SystemMonitoringService)?
    private let systemPreferences: SystemMonitorPreferences?
    /// 放宽为 internal：显示偏好订阅与渲染都拆在 MenuBarManager+DisplayPreferences.swift
    let displayPreferences: MenuBarDisplayPreferences
    /// 注入的键值存储（菜单栏偏好与面板分页偏好共用同一份，测试 / 取证可写隔离 suite）
    let storage: any KeyValueStorage
    private let harnessUsage: (any HarnessUsageServicing)?
    /// 外观偏好（主题 / 玻璃 / 渲染档）— 与菜单栏偏好共用同一份存储实例
    let appearancePreferences: AppearancePreferences
    /// 系统指标采样周期（秒）— 由渲染档给出（原为只读偏好值，现随档位变）
    // 放宽为 internal：渲染档切换在 +DisplayPreferences 扩展里改写它
    var systemSampleInterval: TimeInterval
    private var lastSystemPoll: Date = .distantPast
    private var timer: Timer?
    /// 当前定时器周期（秒）— 恢复默认值后需按偏好重建，故单独记账
    // 放宽为 internal：定时器重建与偏好订阅拆在 MenuBarManager+DisplayPreferences.swift
    var timerInterval: TimeInterval = 0
    /// 菜单栏显示偏好变更观察者（注册与移除都在 +DisplayPreferences 扩展文件）
    nonisolated(unsafe) var displayPreferencesObserver: NSObjectProtocol?

    /// 剪贴板历史面板入口（由组合根装配）
    var onOpenClipboardHistory: (() -> Void)?
    /// 统一设置窗口入口（由组合根装配；参数 nil = 默认页）
    var onOpenSettings: ((SettingsSection?) -> Void)?

    // MARK: - 初始化

    init(networkMonitor: any NetworkMonitoringService,
         processMonitor: any ProcessNetworkMonitoringService,
         trafficTracker: any TrafficTrackingService,
         clipboardRepository: any ClipboardRepository,
         paster: ClipboardPaster,
         transferController: TransferController? = nil,
         billingMonitor: BillingMonitor? = nil,
         harnessUsage: (any HarnessUsageServicing)? = nil,
         systemMonitor: (any SystemMonitoringService)? = nil,
         systemPreferences: SystemMonitorPreferences? = nil,
         storage: any KeyValueStorage = MenuBarManager.preferredStorage(),
         logger: LoggingService = AppContext.shared.logger) {
        self.monitor = networkMonitor
        self.processMonitor = processMonitor
        self.trafficTracker = trafficTracker
        self.systemMonitor = systemMonitor
        self.systemPreferences = systemPreferences
        self.storage = storage
        self.displayPreferences = MenuBarDisplayPreferences(storage: storage)
        self.harnessUsage = harnessUsage
        let appearance = AppearancePreferences(storage: storage)
        self.appearancePreferences = appearance
        // 采样周期以渲染档为准（设置页的系统页下拉标注为「由渲染档接管」）
        self.systemSampleInterval = appearance.renderProfile.sampleInterval
        self.logger = logger
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.panel = MenuPanelController(networkMonitor: networkMonitor,
                                         processMonitor: processMonitor,
                                         trafficTracker: trafficTracker,
                                         repository: clipboardRepository,
                                         paster: paster,
                                         transferController: transferController,
                                         billingMonitor: billingMonitor,
                                         harnessUsage: harnessUsage,
                                         systemMonitor: systemMonitor,
                                         systemPreferences: systemPreferences,
                                         storage: storage,
                                         logger: logger)
        super.init()

        configureStatusItem()
        panel.onOpenClipboardHistory = { [weak self] in self?.onOpenClipboardHistory?() }
        panel.onOpenSettings = { [weak self] section in self?.onOpenSettings?(section) }
        setupTimer(interval: appearance.renderProfile.tickInterval)
        observeDisplayPreferenceChanges()
#if DEBUG
        runStatusEvidenceIfRequested()
#endif
    }

    /// 菜单栏偏好存储：默认走全局注入（`AppContext.shared.storage`）
    ///
    /// 仅 DEBUG 取证可变：设置 `NM_EVIDENCE_SUITE` 时改用隔离 suite，
    /// 避免取证脚本改写用户真实的菜单栏 / 面板分页偏好。
    static func preferredStorage() -> any KeyValueStorage {
#if DEBUG
        if let suite = ProcessInfo.processInfo.environment["NM_EVIDENCE_SUITE"], !suite.isEmpty,
           let defaults = UserDefaults(suiteName: suite) {
            return UserDefaultsStorage(defaults: defaults)
        }
#endif
        return AppContext.shared.storage
    }

    nonisolated deinit {
        if let displayPreferencesObserver {
            NotificationCenter.default.removeObserver(displayPreferencesObserver)
        }
    }

    // MARK: - 状态栏配置

    /// 状态栏按钮：左键点击切换面板（不挂 NSMenu，点击外部由 popover 的 transient 行为收起）
    private func configureStatusItem() {
        guard let button = statusItem.button else {
            logger.error("状态栏按钮不可用，面板无法唤起")
            return
        }
        button.target = self
        button.action = #selector(handleStatusButton)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .noImage
    }

    @objc private func handleStatusButton() {
        // 左键：打开/关闭面板；右键：弹出右键菜单（设置等）
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusItemMenu()
        } else {
            togglePanel()
        }
    }

    private lazy var statusItemMenu: NSMenu = {
        let menu = NSMenu()
        let settingsItem = NSMenuItem(title: "设置…", action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = [.command, .option]
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "退出 NetworkMonitor", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = [.command]
        menu.addItem(quitItem)
        return menu
    }()

    private func showStatusItemMenu() {
        guard let button = statusItem.button else { return }
        statusItemMenu.popUp(positioning: nil,
                              at: NSPoint(x: 0, y: button.bounds.height),
                              in: button)
    }

    @objc func openSettingsFromMenu() {
        onOpenSettings?(nil)
    }

    // 放宽为 internal：DEBUG 取证扩展要复用同一条 toggle 路径
    @objc func togglePanel() {
        guard let button = statusItem.button else { return }
        panel.toggle(relativeTo: button.bounds, of: button)
    }


    // MARK: - 预热

    /// 启动后预热一次面板（把首次打开的一次性窗口 / 布局开销提前付掉）
    ///
    /// 延后 1.2 秒：等定时器、首轮采样、Token 索引启动稳定，避免和启动路径抢主线程。
    func schedulePrewarm() {
        // 性能测量模式由测量器自己控制预热时序，这里不抢跑（否则「首次打开」那一轮测不准）
        guard !PanelOpenProbe.requested else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            self?.prewarmPanel()
        }
    }

    /// 预热面板（内部保证只做一次、已展开时跳过）
    func prewarmPanel() {
        guard let button = statusItem.button else { return }
        panel.prewarmPanelIfNeeded(relativeTo: button.bounds, of: button)
    }

    // MARK: - 定时器

    /// 启动 / 重建状态栏刷新定时器（周期来自渲染帧率档：标准 1s / 极致 0.5s / 省电 2s）
    ///
    /// 同一个 Timer 同时驱动状态栏标题与面板 `tick()`，所以档位只需要改这一处周期，
    /// 状态栏与面板的节拍天然一致（改造前周期来自「间隔」偏好，与档位是两套旋钮）。
    ///
    /// 重建前先停掉旧定时器并从 RunLoop 移除：否则同一时刻会有两个定时器各跑一份 update，
    /// 旧的那个永远不会被释放。
    func setupTimer(interval: TimeInterval) {
        let period = MenuBarDisplayLogic.clampedRefreshInterval(interval)
        // invalidate 会同时把定时器从所有 RunLoop 模式中摘除，不会残留两份节拍
        timer?.invalidate()
        let t = Timer(timeInterval: period, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.update()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        timerInterval = period

        // 立即更新一次，避免启动后一个周期内状态栏是空白
        update()
    }

    /// 按刷新周期刷新：网速（状态栏）+ 进程采样 + 面板展开时的分层刷新
    // 放宽为 internal：MenuBarManager+DisplayPreferences.swift 在偏好变更后立即重渲染
    @objc func update() {
        monitor.poll()
        let enabled = displayPreferences.enabledMetrics
        let parts = makeStatusParts(enabled: enabled,
                                    snapshot: systemMonitor?.snapshot,
                                    todayTraffic: trafficTracker.todayRx + trafficTracker.todayTx,
                                    tokenTotals: harnessUsage?.snapshot().totals,
                                    unitStyle: MenuBarDisplayLogic.unitStyle(
                                        fromRawValue: displayPreferences.unitStyle.rawValue))
        let separator: String
        switch displayPreferences.density {
        case .compact: separator = "  "
        case .comfortable: separator = "   "
        case .relaxed: separator = "  ·  "
        }
        var alertPrefix = ""
        if displayPreferences.alertsEnabled {
            let cpu = systemMonitor?.snapshot?.cpu?.totalUsage ?? 0
            let memPct = systemMonitor?.snapshot?.memory.map { m in m.total > 0 ? Double(m.used) / Double(m.total) : 0 } ?? 0
            if (enabled.contains(.cpu) && cpu >= displayPreferences.cpuAlertThreshold) ||
               (enabled.contains(.memory) && memPct >= displayPreferences.memoryAlertThreshold) {
                alertPrefix = "⚠️ "
            }
        }
        // 布局偏好：单行 / 两行（card 在菜单栏高度受限时按两行呈现）
        let body = MenuBarDisplayLogic.statusTitle(
            parts: parts,
            layout: MenuBarDisplayLogic.layout(fromRawValue: displayPreferences.layout.rawValue),
            separator: separator)
        let text = alertPrefix.isEmpty ? body : alertPrefix + body
        let title = NSAttributedString(string: text)
        if statusItem.button?.attributedTitle.string != text {
            statusItem.button?.attributedTitle = title
        }

        // 系统指标采样：按偏好周期节流（poll 内部防重入，采集在后台串行队列执行）
        let now = Date()
        if now.timeIntervalSince(lastSystemPoll) >= systemSampleInterval {
            lastSystemPoll = now
            systemMonitor?.poll()
        }
        // 进程采样（内部 3 秒节流 + 后台队列执行，不阻塞主线程）
        processMonitor.poll()
        // 面板自身按 1 秒 / 5 秒分层刷新（内部按时间差节流，收起时直接返回），与状态栏刷新周期无关
        panel.tick()
    }
}