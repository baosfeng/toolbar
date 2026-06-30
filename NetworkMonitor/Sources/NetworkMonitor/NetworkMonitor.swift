import AppKit
import Darwin
import ServiceManagement
import CoreWLAN
import NetworkMonitorCore

// MARK: - Network Speed Monitor

@MainActor
final class NetworkSpeedMonitor {
    private var previousData: [String: (rx: UInt64, tx: UInt64)] = [:]
    private var previousTimestamp: Date = Date()

    private(set) var downloadSpeed: Double = 0
    private(set) var uploadSpeed: Double = 0
    private(set) var totalRx: UInt64
    private(set) var totalTx: UInt64

    init(totalRx: UInt64 = 0, totalTx: UInt64 = 0) {
        self.totalRx = totalRx
        self.totalTx = totalTx
    }

    func poll() {
        let current = readInterfaceBytes()
        let now = Date()
        let elapsed = now.timeIntervalSince(previousTimestamp)
        guard elapsed > 0 else { return }

        var totalRxDiff: UInt64 = 0
        var totalTxDiff: UInt64 = 0

        for (iface, (rx, tx)) in current {
            if let prev = previousData[iface] {
                let rxDiff = rx >= prev.rx ? rx - prev.rx : rx
                let txDiff = tx >= prev.tx ? tx - prev.tx : tx
                totalRxDiff &+= rxDiff
                totalTxDiff &+= txDiff
                totalRx &+= rxDiff
                totalTx &+= txDiff
            }
            previousData[iface] = (rx, tx)
        }

        let currentIfaces = Set(current.keys)
        previousData = previousData.filter { currentIfaces.contains($0.key) }

        downloadSpeed = Double(totalRxDiff) / elapsed
        uploadSpeed = Double(totalTxDiff) / elapsed
        previousTimestamp = now
    }

    private func readInterfaceBytes() -> [String: (rx: UInt64, tx: UInt64)] {
        var result: [String: (rx: UInt64, tx: UInt64)] = [:]
        var ifaddr: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return result }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let current = ptr {
            let name = String(cString: current.pointee.ifa_name)
            if name != "lo0",
               let addr = current.pointee.ifa_addr,
               addr.pointee.sa_family == AF_LINK,
               let data = current.pointee.ifa_data?.assumingMemoryBound(to: if_data.self)
            {
                let d = data.pointee
                result[name] = (UInt64(d.ifi_ibytes), UInt64(d.ifi_obytes))
            }
            ptr = current.pointee.ifa_next
        }
        return result
    }
}

// MARK: - Per-Process Network Monitor

@MainActor
final class ProcessNetworkMonitor {
    private var previous: [Int32: (UInt64, UInt64)] = [:]
    private(set) var processSpeeds: [ProcessNetUsage] = []
    private var lastUpdateTime: Date?

    func poll() {
        guard let snapshot = try? runNettopSnapshot(), !snapshot.isEmpty else { return }

        let now = Date()
        let elapsed: Double
        if let last = lastUpdateTime {
            elapsed = now.timeIntervalSince(last)
        } else {
            elapsed = 1.0
        }
        lastUpdateTime = now

        var speeds: [ProcessNetUsage] = []
        for current in snapshot {
            if let prev = previous[current.pid] {
                let deltaIn = current.bytesIn >= prev.0 ? current.bytesIn - prev.0 : 0
                let deltaOut = current.bytesOut >= prev.1 ? current.bytesOut - prev.1 : 0
                let speedIn = Double(deltaIn) / elapsed
                let speedOut = Double(deltaOut) / elapsed
                if speedIn > 0 || speedOut > 0 {
                    speeds.append(ProcessNetUsage(
                        name: current.name, pid: current.pid,
                        bytesIn: UInt64(speedIn), bytesOut: UInt64(speedOut)
                    ))
                }
            }
            previous[current.pid] = (current.bytesIn, current.bytesOut)
        }
        speeds.sort(by: { $0.total > $1.total })
        processSpeeds = speeds

        let currentPids = Set(snapshot.map { $0.pid })
        previous = previous.filter { currentPids.contains($0.key) }
    }
}


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

    // MARK: - macMonitor 菜单标签
    private let macMonitorHeaderTag: Int = 5000
    private let macMonitorSummaryTag: Int = 5001
    private let macMonitorCPUTag: Int = 5002
    private let macMonitorNetTag: Int = 5003

    private let processSectionTag: Int = 2000
    private let launchAtStartupTag: Int = 3001
    private let maxProcessItems: Int = 10

    private static let launchPrefKey = "launchAtStartup"
    private static let totalRxKey = "totalRx"
    private static let totalTxKey = "totalTx"

    private func getWiFiStatus() -> String {
        if let ssid = CWWiFiClient.shared().interface()?.ssid(), !ssid.isEmpty {
            return ssid
        }
        if getLocalIPAddress() != nil {
            return "已连接"
        }
        return "未连接"
    }

    private var downHistory: [Double] = []
    private var upHistory: [Double] = []
    private let maxHistory: Int = 60

    private var logEntries: [NetworkLogEntry] = []

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

    private func menuItem(title: String, action: Selector? = nil, keyEquivalent: String = "",
                          symbol: String? = nil, tag: Int = 0, isEnabled: Bool = true) -> NSMenuItem {
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

    private func setupMenu() {
        let menu = NSMenu()

        // ── Header ──
        let headerItem = NSMenuItem(title: "网速&电池", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        // ── Battery Status ──
        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem(title: "🔋 电池: —%", tag: 200, isEnabled: false))
        menu.addItem(menuItem(title: "⏱ 剩余时间: —", tag: 201, isEnabled: false))
        menu.addItem(menuItem(title: "⚡ 电源: —", tag: 202, isEnabled: false))
        menu.addItem(menuItem(title: "🔄 循环: —次", tag: 203, isEnabled: false))
        menu.addItem(menuItem(title: "❤️ 健康: —", tag: 204, isEnabled: false))

        // ── Network Status ──
        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem(title: "📶 IP: 获取中…", tag: 1002, isEnabled: false))
        menu.addItem(menuItem(title: "📶 Wi-Fi: —", tag: 1004, isEnabled: false))
        menu.addItem(menuItem(title: "▼ 0 KB/s  ▲ 0 KB/s", tag: 1001, isEnabled: false))
        menu.addItem(menuItem(title: "", tag: 1003, isEnabled: false))

        // ── Active Processes ──
        let procHeader = NSMenuItem(title: "活跃进程", action: nil, keyEquivalent: "")
        procHeader.isEnabled = false
        procHeader.tag = processSectionTag
        menu.addItem(procHeader)

        // ── macMonitor 本机监控 ──
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "📊 本机监控", action: nil, keyEquivalent: ""))
        menu.addItem(menuItem(title: "⏱  活跃: —    ⌨️ 击键: —", tag: macMonitorSummaryTag, isEnabled: false))
        menu.addItem(menuItem(title: "💡 亮屏: —    🌙 息屏: —", tag: macMonitorSummaryTag + 1, isEnabled: false))
        menu.addItem(menuItem(title: "💻 CPU: —   内存: —", tag: macMonitorCPUTag, isEnabled: false))
        menu.addItem(menuItem(title: "📶 ↑ —/s   ↓ —/s", tag: macMonitorNetTag, isEnabled: false))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem(title: "📅 生成每日报告", action: #selector(generateDailyReport), symbol: "doc.text"))
        menu.addItem(menuItem(title: "📆 生成每周报告", action: #selector(generateWeeklyReport), symbol: "calendar"))
        menu.addItem(menuItem(title: "📂 打开报告文件夹", action: #selector(openReportsFolder), symbol: "folder"))

        // ── Actions ──
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

    private func setupTimer() {
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.update()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// 启动 macMonitor 本机监控引擎
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

    @objc private func update() {
        // Poll battery
        batteryMonitor.poll()
        let battery = batteryMonitor.status

        // Poll network
        monitor.poll()
        let downSpeed = max(monitor.downloadSpeed, 0)
        let upSpeed = max(monitor.uploadSpeed, 0)
        let downStr = formatSpeedShort(downSpeed)
        let upStr = formatSpeedShort(upSpeed)

        // Update menu bar view
        labelView.update(battery: battery, downSpeed: downStr, upSpeed: upStr)

        // History
        downHistory.append(downSpeed)
        upHistory.append(upSpeed)
        if downHistory.count > maxHistory { downHistory.removeFirst() }
        if upHistory.count > maxHistory { upHistory.removeFirst() }

        // Logging
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

        // Process monitor
        processMonitor.poll()
        let processes = processMonitor.processSpeeds
        let ip = getLocalIPAddress()
        let wifi = getWiFiStatus()

        guard let menu = statusItem.menu else { return }

        // ── Update menu items ──

        // Launch at startup
        if let launchItem = menu.item(withTag: launchAtStartupTag) {
            launchItem.state = isLaunchAtStartupSaved ? .on : .off
        }

        // Battery items
        if let item = menu.item(withTag: 200) {
            item.title = "🔋 \(battery.percentage)%"
        }
        if let item = menu.item(withTag: 201) {
            item.title = "⏱ \(battery.timeLabel)"
        }
        if let item = menu.item(withTag: 202) {
            let src = battery.powerSource == "AC Power" ? "交流电" : "电池"
            let charging = battery.isCharging ? " ⚡充电中" : battery.isCharged ? " ✅已充满" : ""
            item.title = "⚡ \(src)\(charging)"
        }
        if let item = menu.item(withTag: 203) {
            item.title = "🔄 循环: \(battery.cycleCount)次"
        }
        if let item = menu.item(withTag: 204) {
            item.title = "❤️ 健康: \(battery.health)"
        }

        // Network items
        if let ipItem = menu.item(withTag: 1002) {
            ipItem.title = ip.map { "📶 \($0)" } ?? "📶 未连接"
        }
        if let wifiItem = menu.item(withTag: 1004) {
            wifiItem.title = "📶 \(wifi)"
        }
        if let detailsItem = menu.item(withTag: 1001) {
            let downFull = formatBytesFull(UInt64(downSpeed)) + "/s"
            let upFull = formatBytesFull(UInt64(upSpeed)) + "/s"
            detailsItem.title = "▼ \(downFull)    ▲ \(upFull)"
            let attrStr = NSMutableAttributedString(string: detailsItem.title)
            let fullRange = NSRange(location: 0, length: attrStr.length)
            attrStr.addAttribute(.font, value: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular), range: fullRange)
            detailsItem.attributedTitle = attrStr
        }
        if let trendItem = menu.item(withTag: 1003) {
            let totalHistory = zip(downHistory, upHistory).map { $0 + $1 }
            if !totalHistory.isEmpty {
                trendItem.title = "\(sparkline(from: totalHistory, maxChars: 10))"
            }
        }

        // Header (show totals)
        if let headerItem = menu.item(at: 0) {
            let totalDown = formatBytesFull(monitor.totalRx)
            let totalUp = formatBytesFull(monitor.totalTx)
            let attrStr = NSMutableAttributedString(string: "网速&电池  ↓\(totalDown)  ↑\(totalUp)")
            let fullRange = NSRange(location: 0, length: attrStr.length)
            attrStr.addAttribute(.font, value: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium), range: fullRange)
            headerItem.attributedTitle = attrStr
        }

        // ── Update macMonitor menu items (每10秒刷新一次) ──
        if Int(Date().timeIntervalSince1970).isMultiple(of: 10) {
            updateMacMonitorMenu(menu: menu)
        }

        updateProcessItems(menu: menu, processes: processes)

        // Update detail panel if open
        if let panel = detailPanel, panel.isVisible {
            panel.update(
                battery: battery,
                downSpeed: downSpeed, upSpeed: upSpeed,
                totalRx: monitor.totalRx, totalTx: monitor.totalTx,
                ip: ip, wifi: wifi, processes: processes
            )
        }
    }

    private func updateProcessItems(menu: NSMenu, processes: [ProcessNetUsage]) {
        while let item = menu.item(withTag: processSectionTag + 1) {
            menu.removeItem(item)
        }

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
            item.tag = processSectionTag + 1

            if let appPath = NSWorkspace.shared.urlForApplication(withBundleIdentifier: process.name) ??
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: guessBundleID(for: process.name)) {
                let icon = NSWorkspace.shared.icon(forFile: appPath.path)
                icon.size = NSSize(width: 14, height: 14)
                item.image = icon
            }

            let headerIndex = menu.indexOfItem(withTag: processSectionTag)
            if headerIndex >= 0 {
                menu.insertItem(item, at: headerIndex + 1)
            }
        }

        if top.isEmpty {
            let item = NSMenuItem(title: "暂无活跃流量", action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.tag = processSectionTag + 1
            let headerIdx = menu.indexOfItem(withTag: processSectionTag)
            if headerIdx >= 0 {
                menu.insertItem(item, at: headerIdx + 1)
            }
        }
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
        网速&电池
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

    /// 更新 macMonitor 菜单项
    private func updateMacMonitorMenu(menu: NSMenu) {
        let stats = statsProvider.fetchTodayStats()

        let active = formatDurationCompact(stats.activeSeconds)
        let keys = formatCompactNumber(stats.keyPressCount)
        if let item = menu.item(withTag: macMonitorSummaryTag) {
            item.title = "⏱  活跃: \(active)    ⌨️ 击键: \(keys)"
        }
        if let item = menu.item(withTag: macMonitorSummaryTag + 1) {
            item.title = "💡 亮屏: \(formatDurationCompact(stats.screenOnSeconds))    🌙 息屏: \(formatDurationCompact(stats.screenOffSeconds))"
        }
        if let item = menu.item(withTag: macMonitorCPUTag) {
            item.title = "💻 CPU: \(String(format: "%.1f", stats.cpuUsage))%   内存: \(stats.memoryUsedMB)MB/\(stats.memoryTotalMB)MB"
        }
        if let item = menu.item(withTag: macMonitorNetTag) {
            item.title = "📶 ↑ \(formatSpeedShort(Double(stats.netUploadSpeed)))/s   ↓ \(formatSpeedShort(Double(stats.netDownloadSpeed)))/s"
        }
    }

    // MARK: - 格式化辅助

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

    // MARK: - macMonitor 操作

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

    nonisolated deinit {}
}
