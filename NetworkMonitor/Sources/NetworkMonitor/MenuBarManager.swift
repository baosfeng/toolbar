import AppKit
import NetworkMonitorCore

// MARK: - Menu Bar Manager

/// 菜单栏 UI 总控制器 — 状态栏网速显示 + 下拉面板生命周期
///
/// 状态栏只显示 ↑↓ 网速（`StatusBarView`）；点击按钮展开 `MenuPanelController` 的
/// NSPopover 自定义面板（网络 / 剪贴板 / 传送 / 额度 / Token / 系统六页），不再使用 NSMenu。
@MainActor
final class MenuBarManager: NSObject {

    private let statusItem: NSStatusItem
    private let monitor: any NetworkMonitoringService
    private let processMonitor: any ProcessNetworkMonitoringService
    private let trafficTracker: any TrafficTrackingService
    private let panel: MenuPanelController
    private let logger: LoggingService
    /// 系统指标采样服务（nil = 未装配；采样频率跟随偏好周期）
    private let systemMonitor: (any SystemMonitoringService)?
    private let systemPreferences: SystemMonitorPreferences?
    private let displayPreferences: MenuBarDisplayPreferences
    private let harnessUsage: (any HarnessUsageServicing)?
    /// 系统指标采样周期（秒）— 由偏好给出，1 秒链按此节流
    private let systemSampleInterval: TimeInterval
    private var lastSystemPoll: Date = .distantPast
    private var timer: Timer?

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
         logger: LoggingService = AppContext.shared.logger) {
        self.monitor = networkMonitor
        self.processMonitor = processMonitor
        self.trafficTracker = trafficTracker
        self.systemMonitor = systemMonitor
        self.systemPreferences = systemPreferences
        self.displayPreferences = MenuBarDisplayPreferences(storage: AppContext.shared.storage)
        self.harnessUsage = harnessUsage
        self.systemSampleInterval = systemPreferences?.sampleInterval
            ?? SystemMonitorPreferences.defaultSampleInterval
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
                                         logger: logger)
        super.init()

        configureStatusItem()
        panel.onOpenClipboardHistory = { [weak self] in self?.onOpenClipboardHistory?() }
        panel.onOpenSettings = { [weak self] section in self?.onOpenSettings?(section) }
        setupTimer()
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

    @objc private func togglePanel() {
        guard let button = statusItem.button else { return }
        panel.toggle(relativeTo: button.bounds, of: button)
    }

#if DEBUG
    /// 取证专用（仅 DEBUG）：走与点击状态栏完全相同的 toggle 路径打开面板
    func openPanelForEvidence() {
        togglePanel()
    }

    /// 取证专用（仅 DEBUG）：popover 窗口号与 frame
    func evidenceWindow() -> (number: Int, frame: NSRect)? {
        panel.evidenceWindow()
    }

    /// 取证专用（仅 DEBUG）：强制 popover 外观（浅色/深色）
    func forceAppearanceForEvidence(_ name: NSAppearance.Name) {
        panel.forceAppearanceForEvidence(name)
    }

    /// 取证专用（仅 DEBUG）：切换到指定分页
    func selectTabForEvidence(_ tab: MenuPanelTab) {
        panel.selectTabForEvidence(tab)
    }

    /// 取证专用（仅 DEBUG）：强制空态（进程 / 剪贴板）
    func forceEmptyForEvidence() {
        panel.forceEmptyDataForEvidence = true
    }

    /// 测量专用（仅 DEBUG）：面板当前是否展开
    var isPanelShownForMeasure: Bool { panel.isShown }

    /// 测量专用（仅 DEBUG）：收起面板（关掉上一轮，准备下一次测量）
    func closePanelForMeasure() {
        panel.close()
    }

    /// 测量专用（仅 DEBUG）：popover 内容窗口（强制首帧落屏用）
    func panelWindowForMeasure() -> NSWindow? {
        panel.measurePanelWindow()
    }

    /// 测量专用（仅 DEBUG）：popover 当前内容尺寸（核对高度是否已按内容订好）
    var panelContentSizeForMeasure: NSSize { panel.popover.contentSize }
#endif

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

    private func setupTimer() {
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.update()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        // 立即更新一次，避免启动后 1 秒空白
        update()
    }

    /// 每秒刷新：网速（状态栏）+ 进程采样 + 面板展开时的分层刷新
    @objc private func update() {
        monitor.poll()
        let downSpeed = max(monitor.downloadSpeed, 0)
        let upSpeed = max(monitor.uploadSpeed, 0)
        let enabled = displayPreferences.enabledMetrics
        let downSpeedSafe = max(monitor.downloadSpeed, 0)
        let upSpeedSafe = max(monitor.uploadSpeed, 0)
        var parts: [String] = []
        if enabled.contains(.downSpeed) { parts.append("↓" + formatSpeedShort(downSpeedSafe)) }
        if enabled.contains(.upSpeed) { parts.append("↑" + formatSpeedShort(upSpeedSafe)) }
        let snap = systemMonitor?.snapshot
        if enabled.contains(.cpu), let cpu = snap?.cpu?.totalUsage { parts.append("CPU " + String(Int((cpu * 100).rounded())) + "%") }
        if enabled.contains(.gpu), let gpu = snap?.gpu { parts.append("GPU " + String(Int((gpu.utilization * 100).rounded())) + "%") }
        if enabled.contains(.memory), let mem = snap?.memory, mem.total > 0 { parts.append("MEM " + String(Int((Double(mem.used) / Double(mem.total) * 100).rounded())) + "%") }
        if enabled.contains(.memoryPressure), let mem = snap?.memory { parts.append("P " + mem.pressure.rawValue) }
        if enabled.contains(.diskFree), let disk = snap?.disk { parts.append("Disk " + String(format: "%.1f", Double(disk.total - disk.used) / 1073741824.0) + "G") }
        if enabled.contains(.diskIO), let disk = snap?.disk {
            if let r = disk.readBytesPerSecond { parts.append("R " + formatSpeedShort(r)) }
            if let w = disk.writeBytesPerSecond { parts.append("W " + formatSpeedShort(w)) }
        }
        if enabled.contains(.wifi), let wifi = snap?.wifi { parts.append("WiFi " + String(wifi.rssiDBm) + "dBm") }
        if enabled.contains(.battery), let bat = snap?.battery, let p = bat.percentage { parts.append("BAT " + String(Int((p * 100).rounded())) + "%") }
        if enabled.contains(.thermal), let t = snap?.thermal, let c = t.cpuTemperatureCelsius { parts.append("Temp " + String(Int(c.rounded())) + "°C") }
        if enabled.contains(.todayTraffic) { parts.append("Today " + formatSpeedShort(Double(trafficTracker.todayRx + trafficTracker.todayTx))) }
        if enabled.contains(.tokenToday) { parts.append("Token " + formatSpeedShort(Double(harnessUsage?.snapshot().totals.today.totalTokens ?? 0))) }
        if enabled.contains(.tokenCacheHit), let rate = harnessUsage?.snapshot().totals.cacheHitRate { parts.append("HIT " + String(Int((rate * 100).rounded())) + "%") }
        if enabled.contains(.tokenWeek) { parts.append("7d " + formatSpeedShort(Double(harnessUsage?.snapshot().totals.thisWeek.totalTokens ?? 0))) }
        if parts.isEmpty { parts.append(formatSpeedShort(downSpeedSafe)) }
        let separator: String
        switch displayPreferences.density {
        case .compact: separator = "  "
        case .comfortable: separator = "   "
        case .relaxed: separator = "  ·  "
        }
        let text = parts.joined(separator: separator)
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
        // 面板自身按 1 秒 / 5 秒分层刷新（收起时内部直接返回）
        panel.tick()
    }
}