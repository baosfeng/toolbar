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
///   操作项 / 退出
@MainActor
final class MenuBarManager: NSObject {
    private let statusItem: NSStatusItem
    private var monitor: NetworkSpeedMonitor!
    private let processMonitor = ProcessNetworkMonitor()
    private var timer: Timer?

    // MARK: - 子菜单
    private let processSubmenu = NSMenu()

    // MARK: - 菜单标签
    private let networkIPTag = 1002
    private let networkWiFiTag = 1004

    private let launchAtStartupTag = 3001
    private let maxProcessItems = 10

    private static let launchPrefKey = "launchAtStartup"
    private static let totalRxKey = "totalRx"
    private static let totalTxKey = "totalTx"

    // MARK: - 每日流量追踪
    private static let dayStartDateKey = "dayStartDate"
    private static let dayStartRxKey = "dayStartRx"
    private static let dayStartTxKey = "dayStartTx"
    private static let dailyLogKey = "dailyTrafficLog"

    private var downHistory: [Double] = []
    private var upHistory: [Double] = []
    private let maxHistory = 60


    // MARK: - 每日流量追踪
    private var dayStartRx: UInt64 = 0
    private var dayStartTx: UInt64 = 0
    private let trafficSubmenu = NSMenu()
    private let trafficTodayTag = 8001


    // MARK: - 初始化

    override init() {
        let savedRx = UInt64(UserDefaults.standard.integer(forKey: Self.totalRxKey))
        let savedTx = UInt64(UserDefaults.standard.integer(forKey: Self.totalTxKey))
        monitor = NetworkSpeedMonitor(totalRx: savedRx, totalTx: savedTx)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        loadDailyTraffic()
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
        menu.addItem(menuItem(title: "Wi-Fi: —", symbol: "wifi", tag: networkWiFiTag, isEnabled: false))

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

    @objc private func update() {
        // 网速
        monitor.poll()
        let downSpeed = max(monitor.downloadSpeed, 0)
        let upSpeed = max(monitor.uploadSpeed, 0)
        let downStr = formatSpeedShort(downSpeed)
        let upStr = formatSpeedShort(upSpeed)

        // 更新菜单栏属性字符串
        statusItem.button?.attributedTitle = StatusBarView.attributedString(downSpeed: downStr, upSpeed: upStr)

        // 历史记录
        downHistory.append(downSpeed)
        upHistory.append(upSpeed)
        if downHistory.count > maxHistory { downHistory.removeFirst() }
        if upHistory.count > maxHistory { upHistory.removeFirst() }

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

        // 标题栏（显示今日流量）
        if let headerItem = menu.item(at: 0) {
            let todayDown = formatBytesFull(todayRx)
            let todayUp = formatBytesFull(todayTx)
            let attrStr = NSMutableAttributedString(string: "今日  ↓\(todayDown)  ↑\(todayUp)")
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

        // ── 更新流量汇总子菜单
        updateDailyTraffic()
        updateTrafficSubmenu()

        // 进程列表
        updateProcessItems(processes: processes)

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

    // MARK: - 每日流量追踪

    /// 加载或初始化每日流量追踪
    private func loadDailyTraffic() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        dayStartRx = UInt64(UserDefaults.standard.integer(forKey: Self.dayStartRxKey))
        dayStartTx = UInt64(UserDefaults.standard.integer(forKey: Self.dayStartTxKey))

        // 首次启动：以当前总量为今日起点
        if dayStartRx == 0, dayStartTx == 0 {
            dayStartRx = monitor.totalRx
            dayStartTx = monitor.totalTx
            UserDefaults.standard.set(today, forKey: Self.dayStartDateKey)
            UserDefaults.standard.set(Int(dayStartRx), forKey: Self.dayStartRxKey)
            UserDefaults.standard.set(Int(dayStartTx), forKey: Self.dayStartTxKey)
        }
    }

    /// 检查日期变更，切换并保存每日日志
    private func updateDailyTraffic() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let savedDate = UserDefaults.standard.object(forKey: Self.dayStartDateKey) as? Date ?? today

        guard !cal.isDate(savedDate, inSameDayAs: today) else { return }

        // 日期变了 — 保存昨天的流量到日志
        let yesterdayRx = dayStartRx > 0 && monitor.totalRx >= dayStartRx
            ? monitor.totalRx - dayStartRx : 0
        let yesterdayTx = dayStartTx > 0 && monitor.totalTx >= dayStartTx
            ? monitor.totalTx - dayStartTx : 0

        if yesterdayRx > 0 || yesterdayTx > 0 {
            var log = UserDefaults.standard.array(forKey: Self.dailyLogKey) as? [[String: Any]] ?? []
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            log.append(["date": fmt.string(from: savedDate), "rx": yesterdayRx, "tx": yesterdayTx])
            // 保留最近 30 天
            if log.count > 30 { log = Array(log.suffix(30)) }
            UserDefaults.standard.set(log, forKey: Self.dailyLogKey)
        }

        // 重置今日起点
        dayStartRx = monitor.totalRx
        dayStartTx = monitor.totalTx
        UserDefaults.standard.set(today, forKey: Self.dayStartDateKey)
        UserDefaults.standard.set(Int(dayStartRx), forKey: Self.dayStartRxKey)
        UserDefaults.standard.set(Int(dayStartTx), forKey: Self.dayStartTxKey)
    }

    /// 今日流量（下行）
    private var todayRx: UInt64 {
        monitor.totalRx >= dayStartRx ? monitor.totalRx - dayStartRx : 0
    }

    /// 今日流量（上行）
    private var todayTx: UInt64 {
        monitor.totalTx >= dayStartTx ? monitor.totalTx - dayStartTx : 0
    }

    /// 近 7 日每日流量明细（日期降序：今天在最前）
    private var weekEntries: [(label: String, rx: UInt64, tx: UInt64)] {
        var entries: [(label: String, rx: UInt64, tx: UInt64)] = []
        let fmt = DateFormatter()
        fmt.dateFormat = "M/d"

        // 今天
        entries.append((label: fmt.string(from: Date()), rx: todayRx, tx: todayTx))

        // 从日志取前 6 天
        let log = UserDefaults.standard.array(forKey: Self.dailyLogKey) as? [[String: Any]] ?? []
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        for entry in log.reversed() {
            guard let dateStr = entry["date"] as? String,
                  let date = dateFmt.date(from: dateStr),
                  let rx = entry["rx"] as? UInt64,
                  let tx = entry["tx"] as? UInt64 else { continue }
            let daysDiff = cal.dateComponents([.day], from: date, to: today).day ?? 7
            guard daysDiff > 0, daysDiff < 7 else { continue }
            entries.append((label: fmt.string(from: date), rx: rx, tx: tx))
        }

        return entries
    }

    /// 构建流量汇总子菜单
    private func buildTrafficSubmenu() {
        trafficSubmenu.removeAllItems()
        trafficSubmenu.addItem(menuItem(title: "今日: —", symbol: "sun.max", tag: trafficTodayTag, isEnabled: false))
    }

    /// 更新流量汇总子菜单（今日 + 近7日逐日明细）
    private func updateTrafficSubmenu() {
        trafficSubmenu.removeAllItems()

        // 今日
        let todayDown = formatBytesFull(todayRx)
        let todayUp = formatBytesFull(todayTx)
        trafficSubmenu.addItem(menuItem(title: "今日  ↓\(todayDown)  ↑\(todayUp)", symbol: "sun.max", tag: trafficTodayTag, isEnabled: false))

        // 近7日逐日明细（weekEntries[0] 是今天，已单独显示）
        let entries = weekEntries
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




    nonisolated deinit {}
}
