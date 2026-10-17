import AppKit
import NetworkMonitorCore
import ServiceManagement

// MARK: - Menu Bar Manager

/// UI 总控制器 — 管理状态栏、下拉菜单及所有监控引擎
///
/// 菜单结构：今日流量 → IP → 活跃进程 ▶ → 流量汇总 ▶ → 剪贴板入口 → 开机自启动 → 退出
@MainActor
final class MenuBarManager: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let monitor: NetworkMonitoringService
    private let processMonitor: any ProcessNetworkMonitoringService
    private let trafficTracker: any TrafficTrackingService
    private var timer: Timer?

    /// 日志服务
    private let logger: LoggingService

    /// 偏好存储（开机自启动状态；禁止直读 UserDefaults.standard）
    private let storage: any KeyValueStorage

    // MARK: - 子菜单
    private let processSubmenu = NSMenu()
    private let trafficSubmenu = NSMenu()

    // MARK: - 菜单标签
    private let networkIPTag = 1002
    private let launchAtStartupTag = 3001
    /// 剪贴板历史入口（面板）+ 剪贴板设置入口
    private let clipboardHistoryTag = 7001
    private let clipboardSettingsTag = 7002
    private let trafficTodayTag = 8001

    /// 剪贴板面板入口（由组合根装配，点击时调用）
    var onOpenClipboardHistory: (() -> Void)?
    /// 剪贴板设置窗入口（由组合根装配）
    var onOpenClipboardSettings: (() -> Void)?

    private let maxProcessItems = 10

    /// 流量汇总菜单内容哈希 — 内容未变化时跳过重建，避免每 5 秒销毁/重建菜单项与 SF Symbol
    private var lastTrafficHash: String = ""

    /// 中频更新间隔（今日流量/IP/进程列表/开机自启状态）
    private static let midInterval: TimeInterval = 5.0
    private var lastMidUpdate: Date = .distantPast

    // MARK: - 初始化

    init(
        networkMonitor: any NetworkMonitoringService,
        processMonitor: any ProcessNetworkMonitoringService,
        trafficTracker: any TrafficTrackingService,
        storage: any KeyValueStorage = AppContext.shared.storage,
        logger: LoggingService = AppContext.shared.logger
    ) {
        self.monitor = networkMonitor
        self.processMonitor = processMonitor
        self.trafficTracker = trafficTracker
        self.storage = storage
        self.logger = logger
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        setupMenu()
        setupTimer()
    }

    // MARK: - 菜单项工厂

    private func menuItem(title: String, action: Selector? = nil, keyEquivalent: String = "",
                          symbol: String? = nil, tag: Int = 0, isEnabled: Bool = true) -> NSMenuItem
    {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        item.tag = tag
        item.isEnabled = isEnabled
        if let symbol {
            if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: title) {
                let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
                let configured = img.withSymbolConfiguration(config) ?? img
                item.image = configured
                item.image?.isTemplate = true
            }
        }
        return item
    }

    // MARK: - 构建菜单

    private func setupMenu() {
        let menu = NSMenu()

        // ── 标题栏 ──
        let headerItem = NSMenuItem(title: "网络监控", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        // ── 网络信息 ──
        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem(title: "IP: 获取中…", symbol: "network", tag: networkIPTag, isEnabled: false))

        // ── 活跃进程（二级菜单） ──
        menu.addItem(NSMenuItem.separator())
        let procItem = menuItem(title: "活跃进程", symbol: "app.connected.to.app.below.fill")
        procItem.submenu = processSubmenu
        menu.addItem(procItem)

        // ── 流量汇总（二级菜单） ──
        menu.addItem(NSMenuItem.separator())
        buildTrafficSubmenu()
        let trafficMenuItem = menuItem(title: "流量汇总", symbol: "arrow.down.arrow.up")
        trafficMenuItem.submenu = trafficSubmenu
        menu.addItem(trafficMenuItem)

        // ── 剪贴板入口 ──
        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem(title: "剪贴板历史", action: #selector(openClipboardHistory),
                              symbol: "doc.on.clipboard", tag: clipboardHistoryTag))
        menu.addItem(menuItem(title: "剪贴板设置…", action: #selector(openClipboardSettings),
                              symbol: "gearshape", tag: clipboardSettingsTag))

        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem(title: "开机自启动", action: #selector(toggleLaunchAtStartup),
                              symbol: "clock.arrow.circlepath", tag: launchAtStartupTag))

        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q",
                              symbol: "power"))

        statusItem.menu = menu
        menu.delegate = self

        if let launchItem = menu.item(withTag: launchAtStartupTag) {
            launchItem.state = isLaunchAtStartupSaved ? .on : .off
        }
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

    // MARK: - 定时更新

    /// 每秒定时刷新 — 网速每秒、中频信息每 5 秒
    @objc private func update() {
        let now = Date()

        // ── 每秒：网速 ──
        monitor.poll()
        let downSpeed = max(monitor.downloadSpeed, 0)
        let upSpeed = max(monitor.uploadSpeed, 0)
        let title = StatusBarView.attributedString(downSpeed: formatSpeedShort(downSpeed),
                                                   upSpeed: formatSpeedShort(upSpeed))
        if statusItem.button?.attributedTitle != title {
            statusItem.button?.attributedTitle = title
        }

        // 进程采样（内部 3 秒节流 + 后台队列执行，不阻塞主线程）
        processMonitor.poll()

        // ── 每 5 秒：中频更新 ──
        if now.timeIntervalSince(lastMidUpdate) >= Self.midInterval {
            lastMidUpdate = now
            updateMidFrequency()
        }
    }

    /// 中频更新（5 秒）：今日流量标题、IP、开机自启、流量汇总、进程列表
    private func updateMidFrequency() {
        guard let menu = statusItem.menu else { return }

        // 开机自启
        if let launchItem = menu.item(withTag: launchAtStartupTag) {
            launchItem.state = isLaunchAtStartupSaved ? .on : .off
        }

        // 标题栏（显示今日流量）
        if let headerItem = menu.item(at: 0) {
            let todayDown = formatBytesFull(trafficTracker.todayRx)
            let todayUp = formatBytesFull(trafficTracker.todayTx)
            let attrStr = NSMutableAttributedString(string: "今日  ↓\(todayDown)  ↑\(todayUp)")
            let fullRange = NSRange(location: 0, length: attrStr.length)
            attrStr.addAttribute(.font, value: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                                 range: fullRange)
            headerItem.attributedTitle = attrStr
        }

        // IP
        if let ipItem = menu.item(withTag: networkIPTag) {
            ipItem.title = getLocalIPAddress() ?? "未连接"
        }

        // 流量汇总
        trafficTracker.update()
        updateTrafficSubmenu()

        // 进程列表
        updateProcessItems(processes: processMonitor.processSpeeds)
    }

    // MARK: - NSMenuDelegate

    /// 菜单打开时强制刷新所有统计，确保看到最新数据
    func menuWillOpen(_ menu: NSMenu) {
        lastMidUpdate = Date()
        updateMidFrequency()
    }

    // MARK: - 进程列表更新

    private func updateProcessItems(processes: [ProcessNetUsage]) {
        processSubmenu.removeAllItems()

        let top = processes.prefix(maxProcessItems)
        for process in top {
            let downStr = formatSpeedShort(Double(process.bytesIn))
            let upStr = formatSpeedShort(Double(process.bytesOut))
            let shortName = process.name.count > 14
                ? String(process.name.prefix(13)) + "…"
                : process.name
            let title = "  \(shortName)  ▼\(downStr)  ▲\(upStr)"

            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.image = AppIconProvider.icon(forProcess: process.name, size: 14)
            processSubmenu.addItem(item)
        }

        if top.isEmpty {
            let item = NSMenuItem(title: "暂无活跃流量", action: nil, keyEquivalent: "")
            item.isEnabled = false
            processSubmenu.addItem(item)
        }
    }

    // MARK: - 流量汇总子菜单

    /// 构建流量汇总子菜单
    private func buildTrafficSubmenu() {
        trafficSubmenu.removeAllItems()
        trafficSubmenu.addItem(menuItem(title: "今日: —", symbol: "sun.max", tag: trafficTodayTag, isEnabled: false))
    }

    /// 更新流量汇总子菜单（今日 + 近7日逐日明细）
    /// 内容未变化时跳过重建（每 5 秒执行一次，避免反复移除/创建菜单项）
    private func updateTrafficSubmenu() {
        let todayDown = formatBytesFull(trafficTracker.todayRx)
        let todayUp = formatBytesFull(trafficTracker.todayTx)
        let entries = trafficTracker.weekEntries

        // 内容哈希：仅变化时才重建
        let hash = "\(todayDown)|\(todayUp)|" + entries
            .map { "\($0.label):\($0.rx):\($0.tx)" }
            .joined(separator: ",")
        guard hash != lastTrafficHash else { return }
        lastTrafficHash = hash

        trafficSubmenu.removeAllItems()
        trafficSubmenu.addItem(menuItem(title: "今日  ↓\(todayDown)  ↑\(todayUp)", symbol: "sun.max",
                                        tag: trafficTodayTag, isEnabled: false))

        if entries.count > 1 {
            trafficSubmenu.addItem(NSMenuItem.separator())
            for i in 1..<entries.count {
                let entry = entries[i]
                trafficSubmenu.addItem(menuItem(
                    title: "\(entry.label)  ↓\(formatBytesFull(entry.rx))  ↑\(formatBytesFull(entry.tx))",
                    symbol: "calendar.day.timeline.left",
                    tag: 0,
                    isEnabled: false
                ))
            }
        }
    }

    // MARK: - Actions

    /// 打开 / 收起剪贴板历史面板
    @objc private func openClipboardHistory() {
        onOpenClipboardHistory?()
    }

    /// 打开剪贴板设置窗
    @objc private func openClipboardSettings() {
        onOpenClipboardSettings?()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    private var isLaunchAtStartupSaved: Bool {
        storage.bool(forKey: ClipboardPreferences.launchAtStartupKey)
    }

    @objc private func toggleLaunchAtStartup() {
        let wasEnabled = isLaunchAtStartupSaved
        storage.set(!wasEnabled, forKey: ClipboardPreferences.launchAtStartupKey)

        do {
            if wasEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            logger.error("开机自启动切换失败: \(error)")
        }

        if let item = statusItem.menu?.item(withTag: launchAtStartupTag) {
            item.state = isLaunchAtStartupSaved ? .on : .off
        }
    }
}
