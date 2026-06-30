import AppKit
import NetworkMonitorCore
import ServiceManagement
import CoreWLAN

// MARK: - Menu Bar Manager

/// UI 总控制器 — 管理状态栏、下拉菜单及所有监控引擎
///
/// 菜单结构：
///   网络监控  ↓12.5GB  ↑3.2GB
///   ────────────────────────
///   ▼ 1.2 MB/s    ▲ 340 KB/s   ← 网速
///   ◉ IP / Wi-Fi / 总计        ← 网络信息
///   ────────────────────────
///   活跃进程                    ← 进程列表
///   ────────────────────────
///   ◉ 电池 >                   ← 二级菜单
///   ◉ 本机监控 >               ← 二级菜单
///   ────────────────────────
///   操作项 / 退出
@MainActor
final class MenuBarManager: NSObject {
    private let statusItem: NSStatusItem
    private let labelView = StatusBarView()
    private var monitor: NetworkSpeedMonitor!
    private let batteryMonitor = BatteryMonitor()
    private let processMonitor = ProcessNetworkMonitor()
    private var timer: Timer?
    private var detailPanel: DetailPanel?

    // MARK: - macMonitor 引擎
    private let databaseManager = DatabaseManager()
    private var eventMonitor: EventMonitor?
    private var keyPressMonitor: KeyPressMonitor?
    private var systemSampler: SystemSampler?
    private lazy var statsProvider = StatsProvider(database: databaseManager)
    private var reportGenerator: ReportGenerator?

    // MARK: - 子菜单
    private let processSubmenu = NSMenu()
    private let batterySubmenu = NSMenu()
    private let macMonitorSubmenu = NSMenu()

    // MARK: - 菜单标签
    private let networkIPTag = 1002
    private let networkWiFiTag = 1004

    private let batteryPercentTag = 210
    private let batteryTimeTag = 211
    private let batteryPowerTag = 212
    private let batteryCycleTag = 213

    private let macMonitorSummaryTag = 5001
    private let macMonitorCPUTag = 5003

    private let launchAtStartupTag = 3001
    private let maxProcessItems = 10

    private static let launchPrefKey = "launchAtStartup"
    private static let totalRxKey = "totalRx"
    private static let totalTxKey = "totalTx"

    private var downHistory: [Double] = []
    private var upHistory: [Double] = []
    private let maxHistory = 60

    private var logEntries: [NetworkLogEntry] = []

    // MARK: - 初始化

    override init() {
        let savedRx = UInt64(UserDefaults.standard.integer(forKey: Self.totalRxKey))
        let savedTx = UInt64(UserDefaults.standard.integer(forKey: Self.totalTxKey))
        monitor = NetworkSpeedMonitor(totalRx: savedRx, totalTx: savedTx)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        setupButton()
        setupMenu()
        setupTimer()
        setupMacMonitor()
    }

    private func setupButton() {
        guard let button = statusItem.button else { return }
        button.title = ""
        button.addSubview(labelView)
        NSLayoutConstraint.activate([
            labelView.topAnchor.constraint(equalTo: button.topAnchor),
            labelView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            labelView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            labelView.bottomAnchor.constraint(equalTo: button.bottomAnchor),
        ])

        let clickRecognizer = NSClickGestureRecognizer(target: self, action: #selector(toggleDetailPanel))
        clickRecognizer.numberOfClicksRequired = 2
        button.addGestureRecognizer(clickRecognizer)
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
        menu.addItem(menuItem(title: "Wi-Fi: —", symbol: "wifi", tag: networkWiFiTag, isEnabled: false))

        // ── 活跃进程（二级菜单） ──
        menu.addItem(NSMenuItem.separator())
        let procItem = menuItem(title: "活跃进程", symbol: "app.connected.to.app.below.fill")
        procItem.submenu = processSubmenu
        menu.addItem(procItem)

        // ── 电池（二级菜单） ──
        menu.addItem(NSMenuItem.separator())
        buildBatterySubmenu()
        let battMenuItem = menuItem(title: "电池", symbol: "battery.75", tag: 0)
        battMenuItem.submenu = batterySubmenu
        menu.addItem(battMenuItem)

        // ── macMonitor 本机监控（二级菜单） ──
        buildMacMonitorSubmenu()
        let macMenuItem = menuItem(title: "本机监控", symbol: "cpu")
        macMenuItem.submenu = macMonitorSubmenu
        menu.addItem(macMenuItem)

        // ── 操作 ──
        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem(title: "打开详情面板", action: #selector(toggleDetailPanel), keyEquivalent: "d",
                              symbol: "info.circle.fill"))
        menu.addItem(menuItem(title: "复制信息", action: #selector(copyNetworkInfo), keyEquivalent: "c",
                              symbol: "doc.on.doc"))
        menu.addItem(menuItem(title: "导出日志…", action: #selector(exportLog), keyEquivalent: "e",
                              symbol: "square.and.arrow.up"))

        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem(title: "开机自启动", action: #selector(toggleLaunchAtStartup),
                              symbol: "clock.arrow.circlepath", tag: launchAtStartupTag))

        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q",
                              symbol: "power"))

        statusItem.menu = menu

        if let launchItem = menu.item(withTag: launchAtStartupTag) {
            launchItem.state = isLaunchAtStartupSaved ? .on : .off
        }
    }

    // MARK: - 电池子菜单

    private func buildBatterySubmenu() {
        batterySubmenu.removeAllItems()
        batterySubmenu.addItem(menuItem(title: "电池: —%", symbol: "battery.75", tag: batteryPercentTag, isEnabled: false))
        batterySubmenu.addItem(menuItem(title: "剩余: —", symbol: "clock", tag: batteryTimeTag, isEnabled: false))
        batterySubmenu.addItem(menuItem(title: "电源: —", symbol: "powerplug", tag: batteryPowerTag, isEnabled: false))
        batterySubmenu.addItem(menuItem(title: "循环: —次    健康: —", symbol: "arrow.counterclockwise", tag: batteryCycleTag, isEnabled: false))
    }

    // MARK: - macMonitor 子菜单

    private func buildMacMonitorSubmenu() {
        macMonitorSubmenu.removeAllItems()
        macMonitorSubmenu.addItem(menuItem(title: "活跃: —    击键: —",
                                           symbol: "clock.fill", tag: macMonitorSummaryTag, isEnabled: false))
        macMonitorSubmenu.addItem(menuItem(title: "亮屏: —    息屏: —",
                                           symbol: "sun.max.fill", tag: macMonitorSummaryTag + 1, isEnabled: false))
        macMonitorSubmenu.addItem(menuItem(title: "CPU: —%    内存: —",
                                           symbol: "cpu", tag: macMonitorCPUTag, isEnabled: false))
        macMonitorSubmenu.addItem(NSMenuItem.separator())
        macMonitorSubmenu.addItem(menuItem(title: "生成每日报告", action: #selector(generateDailyReport), symbol: "doc.text"))
        macMonitorSubmenu.addItem(menuItem(title: "生成每周报告", action: #selector(generateWeeklyReport), symbol: "calendar"))
        macMonitorSubmenu.addItem(menuItem(title: "打开报告文件夹", action: #selector(openReportsFolder), symbol: "folder"))
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
    }

    // MARK: - macMonitor 启动

    private func setupMacMonitor() {
        databaseManager.initialize()

        let monitor = EventMonitor(database: databaseManager)
        monitor.start()
        eventMonitor = monitor

        let keyMonitor = KeyPressMonitor(database: databaseManager)
        if keyMonitor.start() {
            keyPressMonitor = keyMonitor
        }

        let sampler = SystemSampler(database: databaseManager)
        sampler.start()
        systemSampler = sampler

        reportGenerator = ReportGenerator(database: databaseManager, statsProvider: statsProvider)
        print("📊 macMonitor 本机监控已启动")
    }

    // MARK: - 定时更新

    @objc private func update() {
        // 电池
        batteryMonitor.poll()
        let battery = batteryMonitor.status

        // 网速
        monitor.poll()
        let downSpeed = max(monitor.downloadSpeed, 0)
        let upSpeed = max(monitor.uploadSpeed, 0)
        let downStr = formatSpeedShort(downSpeed)
        let upStr = formatSpeedShort(upSpeed)

        // 更新菜单栏视图
        labelView.update(downSpeed: downStr, upSpeed: upStr)

        // 历史记录
        downHistory.append(downSpeed)
        upHistory.append(upSpeed)
        if downHistory.count > maxHistory { downHistory.removeFirst() }
        if upHistory.count > maxHistory { upHistory.removeFirst() }

        // 日志
        let shouldLog = logEntries.isEmpty || Date().timeIntervalSince(logEntries.last!.timestamp) >= 5
        if shouldLog {
            logEntries.append(NetworkLogEntry(
                timestamp: Date(),
                downSpeed: downSpeed, upSpeed: upSpeed,
                totalRx: monitor.totalRx, totalTx: monitor.totalTx,
                ip: getLocalIPAddress()
            ))
            if logEntries.count > 1000 {
                logEntries.removeFirst(logEntries.count - 1000)
            }
            UserDefaults.standard.set(Int(monitor.totalRx), forKey: Self.totalRxKey)
            UserDefaults.standard.set(Int(monitor.totalTx), forKey: Self.totalTxKey)
        }

        // 进程
        processMonitor.poll()
        let processes = processMonitor.processSpeeds
        let ip = getLocalIPAddress()
        let wifi = getWiFiStatus()

        guard let menu = statusItem.menu else { return }

        // ── 更新主菜单项 ──

        // 开机自启
        if let launchItem = menu.item(withTag: launchAtStartupTag) {
            launchItem.state = isLaunchAtStartupSaved ? .on : .off
        }

        // 标题栏（显示累计流量）
        if let headerItem = menu.item(at: 0) {
            let totalDown = formatBytesFull(monitor.totalRx)
            let totalUp = formatBytesFull(monitor.totalTx)
            let attrStr = NSMutableAttributedString(string: "网络监控  ↓\(totalDown)  ↑\(totalUp)")
            let fullRange = NSRange(location: 0, length: attrStr.length)
            attrStr.addAttribute(.font, value: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium), range: fullRange)
            headerItem.attributedTitle = attrStr
        }

        // IP
        if let ipItem = menu.item(withTag: networkIPTag) {
            ipItem.title = ip.map { "\($0)" } ?? "未连接"
        }

        // Wi-Fi
        if let wifiItem = menu.item(withTag: networkWiFiTag) {
            wifiItem.title = wifi
        }

        // ── 更新电池子菜单 ──
        updateBatterySubmenu(battery: battery)

        // ── 更新 macMonitor 子菜单（每 10 秒刷新） ──
        if Int(Date().timeIntervalSince1970).isMultiple(of: 10) {
            updateMacMonitorSubmenu()
        }

        // 进程列表
        updateProcessItems(processes: processes)

        // 详情面板
        if let panel = detailPanel, panel.isVisible {
            panel.update(
                battery: battery,
                downSpeed: downSpeed, upSpeed: upSpeed,
                totalRx: monitor.totalRx, totalTx: monitor.totalTx,
                ip: ip, wifi: wifi, processes: processes
            )
        }
    }

    // MARK: - 更新电池子菜单

    private func updateBatterySubmenu(battery: BatteryStatus) {
        if let item = batterySubmenu.item(withTag: batteryPercentTag) {
            item.title = "电池: \(battery.percentage)%"
            let battName: String
            if battery.isCharging {
                battName = "battery.100.bolt"
            } else if battery.isCharged {
                battName = "battery.100"
            } else if battery.percentage > 75 {
                battName = "battery.75"
            } else if battery.percentage > 50 {
                battName = "battery.50"
            } else if battery.percentage > 25 {
                battName = "battery.25"
            } else {
                battName = "battery.25"
            }
            if let img = NSImage(systemSymbolName: battName, accessibilityDescription: "电池") {
                let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
                item.image = img.withSymbolConfiguration(config) ?? img
                item.image?.isTemplate = true
            }
        }
        if let item = batterySubmenu.item(withTag: batteryTimeTag) {
            item.title = "剩余: \(battery.timeLabel)"
        }
        if let item = batterySubmenu.item(withTag: batteryPowerTag) {
            let src = battery.powerSource == "AC Power" ? "交流电" : "电池"
            let charging = battery.isCharging ? "充电中" : battery.isCharged ? "已充满" : ""
            item.title = "\(src)  \(charging)"
        }
        if let item = batterySubmenu.item(withTag: batteryCycleTag) {
            item.title = "循环: \(battery.cycleCount)次    健康: \(battery.health)"
        }
    }

    // MARK: - 更新 macMonitor 子菜单

    private func updateMacMonitorSubmenu() {
        let stats = statsProvider.fetchTodayStats()

        let active = formatDurationCompact(stats.activeSeconds)
        let keys = formatCompactNumber(stats.keyPressCount)
        if let item = macMonitorSubmenu.item(withTag: macMonitorSummaryTag) {
            item.title = "活跃: \(active)    击键: \(keys)"
        }
        if let item = macMonitorSubmenu.item(withTag: macMonitorSummaryTag + 1) {
            item.title = "亮屏: \(formatDurationCompact(stats.screenOnSeconds))    息屏: \(formatDurationCompact(stats.screenOffSeconds))"
        }
        if let item = macMonitorSubmenu.item(withTag: macMonitorCPUTag) {
            item.title = "CPU: \(String(format: "%.1f", stats.cpuUsage))%    内存: \(stats.memoryUsedMB)MB/\(stats.memoryTotalMB)MB"
        }

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

            if let appPath = NSWorkspace.shared.urlForApplication(withBundleIdentifier: process.name) ??
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: guessBundleID(for: process.name)) {
                let icon = NSWorkspace.shared.icon(forFile: appPath.path)
                icon.size = NSSize(width: 14, height: 14)
                item.image = icon
            }

            processSubmenu.addItem(item)
        }

        if top.isEmpty {
            let item = NSMenuItem(title: "暂无活跃流量", action: nil, keyEquivalent: "")
            item.isEnabled = false
            processSubmenu.addItem(item)
        }
    }

    // MARK: - 辅助方法

    private func getWiFiStatus() -> String {
        if let ssid = CWWiFiClient.shared().interface()?.ssid(), !ssid.isEmpty {
            return ssid
        }
        if getLocalIPAddress() != nil {
            return "已连接"
        }
        return "未连接"
    }

    private func guessBundleID(for processName: String) -> String {
        let map: [String: String] = [
            "Google Chrome": "com.google.Chrome",
            "Safari": "com.apple.Safari",
            "Firefox": "org.mozilla.firefox",
            "iTerm2": "com.googlecode.iterm2",
            "Terminal": "com.apple.Terminal",
            "Finder": "com.apple.Finder",
            "Xcode": "com.apple.dt.Xcode",
            "Slack": "com.tinyspeck.slackmacgap",
            "Spotify": "com.spotify.client",
            "Discord": "com.hnc.Discord",
            "Visual Studio Code": "com.microsoft.VSCode",
            "Code": "com.microsoft.VSCode",
            "VSCode": "com.microsoft.VSCode",
            "QQ": "com.tencent.qq",
            "WeChat": "com.tencent.xinWeChat",
            "Telegram": "ru.keepcoder.Telegram",
            "DingTalk": "com.alibaba.DingTalk",
            "WPS": "com.kingsoft.wpsoffice.mac",
            "Microsoft Word": "com.microsoft.Word",
            "Microsoft Excel": "com.microsoft.Excel",
        ]
        return map[processName] ?? "\(processName)"
    }

    private func formatDurationCompact(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        return h > 0 ? "\(h)h\(m)m" : "\(m)m"
    }

    private func formatCompactNumber(_ number: Int) -> String {
        if number >= 10000 {
            return String(format: "%.1fK", Double(number) / 1000)
        }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: number)) ?? "\(number)"
    }

    // MARK: - Actions

    @objc private func toggleDetailPanel() {
        if let panel = detailPanel, panel.isVisible {
            panel.close()
            detailPanel = nil
        } else {
            let panel = DetailPanel()
            panel.update(
                battery: batteryMonitor.status,
                downSpeed: max(monitor.downloadSpeed, 0),
                upSpeed: max(monitor.uploadSpeed, 0),
                totalRx: monitor.totalRx, totalTx: monitor.totalTx,
                ip: getLocalIPAddress(), wifi: getWiFiStatus(),
                processes: processMonitor.processSpeeds
            )
            panel.makeKeyAndOrderFront(nil)
            detailPanel = panel
        }
    }

    @objc private func copyNetworkInfo() {
        let battery = batteryMonitor.status
        let ip = getLocalIPAddress() ?? "未连接"
        let wifi = getWiFiStatus()
        let down = formatBytesFull(UInt64(monitor.downloadSpeed)) + "/s"
        let up = formatBytesFull(UInt64(monitor.uploadSpeed)) + "/s"
        let totalDown = formatBytesFull(monitor.totalRx)
        let totalUp = formatBytesFull(monitor.totalTx)

        let text = """
        网络监控
        ========
        电池: \(battery.percentage)%  \(battery.timeLabel)
        电源: \(battery.powerSource)
        循环: \(battery.cycleCount)次  健康: \(battery.health)
        ========
        IP: \(ip)
        Wi-Fi: \(wifi)
        下载: \(down)
        上传: \(up)
        累计下载: \(totalDown)
        累计上传: \(totalUp)
        """

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    @objc private func exportLog() {
        let panel = NSSavePanel()
        panel.title = "导出流量日志"
        panel.nameFieldStringValue = "网络监控日志.csv"
        panel.allowedContentTypes = [.commaSeparatedText]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        var csv = NetworkLogEntry.csvHeader + "\n"
        for entry in logEntries {
            csv += entry.csvRow + "\n"
        }

        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            print("导出失败: \(error)")
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    private var isLaunchAtStartupSaved: Bool {
        UserDefaults.standard.bool(forKey: Self.launchPrefKey)
    }

    @objc private func toggleLaunchAtStartup() {
        let wasEnabled = isLaunchAtStartupSaved
        UserDefaults.standard.set(!wasEnabled, forKey: Self.launchPrefKey)

        do {
            if wasEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            print("Failed to toggle launch-at-startup: \(error)")
        }

        if let item = statusItem.menu?.item(withTag: launchAtStartupTag) {
            item.state = isLaunchAtStartupSaved ? .on : .off
        }
    }

    // MARK: - macMonitor 报告

    @objc private func generateDailyReport() {
        if let path = reportGenerator?.generateDailyReport() {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }
    }

    @objc private func generateWeeklyReport() {
        if let path = reportGenerator?.generateWeeklyReport() {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }
    }

    @objc private func openReportsFolder() {
        if let path = reportGenerator?.reportsDirectoryPath {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }
    }

    /// 退出前刷新数据库缓冲区并关闭连接
    func flushBeforeQuit() {
        databaseManager.flush()
        databaseManager.close()
        print("📊 数据库已关闭")
    }

    nonisolated deinit {}
}
