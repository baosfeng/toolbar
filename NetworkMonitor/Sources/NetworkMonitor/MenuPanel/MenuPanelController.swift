import AppKit
import NetworkMonitorCore
import ServiceManagement

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
final class MenuPanelController: NSObject, NSPopoverDelegate, MenuPanelViewDelegate {

    // MARK: 依赖

    private let popover = NSPopover()
    private let content = MenuPanelView()
    private let monitor: any NetworkMonitoringService
    private let processMonitor: any ProcessNetworkMonitoringService
    private let trafficTracker: any TrafficTrackingService
    private let repository: any ClipboardRepository
    private let paster: ClipboardPaster
    private let storage: any KeyValueStorage
    private let logger: LoggingService

    // MARK: 回调（组合根注入）

    /// 打开完整剪贴板历史面板
    var onOpenClipboardHistory: (() -> Void)?
    /// 打开剪贴板设置窗
    var onOpenClipboardSettings: (() -> Void)?

    // MARK: 状态

    /// 折线采样（60 个 1 秒点）
    private var downHistory: [Double] = []
    private var upHistory: [Double] = []
    private static let maxHistory = 60
    /// 中频刷新间隔
    private static let midInterval: TimeInterval = 5.0
    private var lastMidRefresh: Date = .distantPast
    /// 最近一次收起时间 — 用于吞掉「点击状态栏按钮先触发 transient 收起、再触发按钮动作」的重复开合
    private var lastCloseDate: Date = .distantPast
    nonisolated(unsafe) private var clipboardObserver: NSObjectProtocol?

    // MARK: - 初始化

    init(networkMonitor: any NetworkMonitoringService,
         processMonitor: any ProcessNetworkMonitoringService,
         trafficTracker: any TrafficTrackingService,
         repository: any ClipboardRepository,
         paster: ClipboardPaster,
         storage: any KeyValueStorage = AppContext.shared.storage,
         logger: LoggingService = AppContext.shared.logger) {
        self.monitor = networkMonitor
        self.processMonitor = processMonitor
        self.trafficTracker = trafficTracker
        self.repository = repository
        self.paster = paster
        self.storage = storage
        self.logger = logger
        super.init()

        configurePopover()
        wireActions()
        observeClipboardChanges()
    }

    nonisolated deinit {
        if let clipboardObserver {
            NotificationCenter.default.removeObserver(clipboardObserver)
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
        content.clipboardPane.onRequestSettings = { [weak self] in self?.requestClipboardSettings() }
        content.clipboardPane.onRequestHistory = { [weak self] in self?.requestClipboardHistory() }
        content.systemPane.onToggleLaunchAtStartup = { [weak self] in self?.toggleLaunchAtStartup() }
        content.systemPane.onQuit = { NSApplication.shared.terminate(nil) }
    }

    private func observeClipboardChanges() {
        clipboardObserver = NotificationCenter.default.addObserver(
            forName: AppEvents.clipboardChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // 面板收起时不做渲染，下次打开会强制全量刷新
                guard self.popover.isShown else { return }
                self.refreshClipboard()
            }
        }
    }

    // MARK: - 显示 / 收起

    /// 状态栏按钮点击入口：已展开则收起，否则在按钮下方展开
    func toggle(relativeTo rect: NSRect, of view: NSView) {
        if popover.isShown {
            close()
            return
        }
        // transient 行为下，点击状态栏按钮会先自动收起再触发按钮动作：
        // 极短时间内的再次 toggle 视为「本次关闭」的续动作，不再重新展开。
        guard Date().timeIntervalSince(lastCloseDate) > 0.25 else { return }
        show(relativeTo: rect, of: view)
    }

    /// 展开面板并强制全量刷新
    func show(relativeTo rect: NSRect, of view: NSView) {
        // 【时序敏感】必须在 popover 成为 key window 之前同步记录目标 App，
        // 否则 frontmost 会变成本 App，合成的 ⌘V 永远落回自己（见 ClipboardPaster 注释）。
        paster.recordTargetApplication()
        refreshAll()
        popover.show(relativeTo: rect, of: view, preferredEdge: .minY)
        updateContentSize(force: true)
        if let window = popover.contentViewController?.view.window {
            window.makeFirstResponder(content)
        }
    }

    /// 收起面板
    func close() {
        guard popover.isShown else { return }
        popover.performClose(nil)
    }

    /// 是否已展开
    var isShown: Bool { popover.isShown }

    // MARK: - 刷新

    /// 每秒调用（由状态栏定时器驱动）：速率必刷，其余按 5 秒节流
    func tick() {
        guard popover.isShown else { return }
        sampleHistory()
        content.updateSpeeds(down: max(monitor.downloadSpeed, 0),
                             up: max(monitor.uploadSpeed, 0),
                             downHistory: downHistory,
                             upHistory: upHistory)
        let now = Date()
        guard now.timeIntervalSince(lastMidRefresh) >= Self.midInterval else { return }
        lastMidRefresh = now
        refreshMidFrequency()
    }

    /// 全量刷新（面板打开时调用一次）
    private func refreshAll() {
        lastMidRefresh = Date()
        sampleHistory()
        content.updateSpeeds(down: max(monitor.downloadSpeed, 0),
                             up: max(monitor.uploadSpeed, 0),
                             downHistory: downHistory,
                             upHistory: upHistory)
        refreshMidFrequency()
        refreshClipboard()
        updateContentSize(force: true)
    }

    /// 中频刷新：今日流量 / 近 6 日柱状图 / 活跃进程 / 系统信息
    private func refreshMidFrequency() {
        trafficTracker.update()
        let bars = MenuPanelMetrics.recentDays(entries: trafficTracker.weekEntries, limit: 6)
        content.updateTraffic(todayRx: trafficTracker.todayRx,
                              todayTx: trafficTracker.todayTx,
                              dailyBars: bars)
        content.updateProcesses(processMonitor.processSpeeds)
        content.updateSystem(ip: getLocalIPAddress() ?? "",
                             wifi: SystemInfoProvider.wifiDisplayName(),
                             launchAtStartup: isLaunchAtStartupSaved)
    }

    /// 剪贴板刷新：仓储按时间倒序取最近 5 条
    private func refreshClipboard() {
        content.updateClipboardItems(repository.fetchClipboardItems(kind: nil, limit: 5))
    }

    /// 采样折线（仅面板展开时采样，避免无谓累积）
    private func sampleHistory() {
        downHistory.append(max(monitor.downloadSpeed, 0))
        upHistory.append(max(monitor.uploadSpeed, 0))
        if downHistory.count > Self.maxHistory { downHistory.removeFirst(downHistory.count - Self.maxHistory) }
        if upHistory.count > Self.maxHistory { upHistory.removeFirst(upHistory.count - Self.maxHistory) }
    }

    /// 按内容自适应高度（≤ 520pt），高度变化时才调整 popover
    ///
    /// 内容高于 520pt 时不做硬截断：面板内部 NSScrollView 转为垂直滚动（隐式滚动条），
    /// 因此进程数变多 / 字体放大 / 多语言换行时仍能看到全部内容。
    private func updateContentSize(force: Bool = false) {
        content.layoutSubtreeIfNeeded()
        let needed = content.desiredContentHeight
        let height = min(max(needed, 180), MenuPanelStyle.maxHeight)
        guard force || abs(popover.contentSize.height - height) > 0.5 else { return }
        popover.contentSize = NSSize(width: MenuPanelStyle.panelWidth, height: height)
    }

    // MARK: - 动作

    /// 点击条目：收起面板后走与剪贴板面板一致的粘贴路径
    private func paste(_ item: ClipboardItem) {
        close()
        // 面板展开时本 App 会被激活；收起后先把目标 App 拉回前台，
        // 否则合成的 ⌘V 会落回自己（只写剪贴板却不粘贴）。
        if let bundleID = paster.targetBundleID,
           let target = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            target.activate(options: [])
        }
        paster.paste(item, asPlainText: false) { [weak self] outcome in
            let message = outcome.message
            guard let self, !message.isEmpty else { return }
            self.logger.info("菜单面板粘贴：\(message)")
        }
    }

    private func requestClipboardSettings() {
        close()
        onOpenClipboardSettings?()
    }

    private func requestClipboardHistory() {
        close()
        onOpenClipboardHistory?()
    }

    private var isLaunchAtStartupSaved: Bool {
        storage.bool(forKey: ClipboardPreferences.launchAtStartupKey)
    }

    /// 开机自启动切换（SMAppService 注册 / 注销，失败时在剪贴板页给提示）
    private func toggleLaunchAtStartup() {
        let wasEnabled = isLaunchAtStartupSaved
        let target = !wasEnabled
        storage.set(target, forKey: ClipboardPreferences.launchAtStartupKey)

        do {
            if target {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            content.updateSystem(ip: getLocalIPAddress() ?? "",
                                 wifi: SystemInfoProvider.wifiDisplayName(),
                                 launchAtStartup: target)
            updateContentSize()
        } catch {
            // 回滚偏好，避免界面状态与系统真实注册状态不一致
            storage.set(wasEnabled, forKey: ClipboardPreferences.launchAtStartupKey)
            content.updateSystem(ip: getLocalIPAddress() ?? "",
                                 wifi: SystemInfoProvider.wifiDisplayName(),
                                 launchAtStartup: wasEnabled)
            logger.error("开机自启动切换失败: \(error)")
        }
    }

    // MARK: - MenuPanelViewDelegate

    func menuPanelViewDidChangeContent(_ view: MenuPanelView) {
        updateContentSize()
    }

    func menuPanelViewDidRequestClose(_ view: MenuPanelView) {
        close()
    }

    func menuPanelViewDidRequestQuit(_ view: MenuPanelView) {
        NSApplication.shared.terminate(nil)
    }

    func menuPanelViewDidRequestClipboardSettings(_ view: MenuPanelView) {
        requestClipboardSettings()
    }

    // MARK: - NSPopoverDelegate

    func popoverDidClose(_ notification: Notification) {
        lastCloseDate = Date()
        // 收起后清空键盘焦点，下次展开从第一行开始
        content.resetKeyboardFocus()
    }
}
