import AppKit
import NetworkMonitorCore
import ServiceManagement
import DGCharts

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
    private let databaseManager = DatabaseManager()
    private var reasonixHookMonitor: ReasonixHookMonitor?
    private lazy var tokenUsageProvider = TokenUsageProvider(database: databaseManager)
    private var lastHistoryHash: String = ""
    private var lastHourlyHash: String = ""

    // MARK: - 子菜单
    private let processSubmenu = NSMenu()
    private let tokenHistorySubmenu = NSMenu()
    private let aiAnalysisSubmenu = NSMenu()
    private let aiDynamicSubmenu = NSMenu()
    private let aiToolStatsSubmenu = NSMenu()
    private let aiModelSubmenu = NSMenu()
    private let aiProjectSubmenu = NSMenu()

    // MARK: - 菜单标签
    private let networkIPTag = 1002

    private let launchAtStartupTag = 3001
    private let tokenSummaryTag = 4001
    private let tokenHourBaseTag = 4200

    // MARK: - AI 分析标签
    private let aiDynamicTag = 5100
    private let aiToolStatsTag = 5101
    private let aiModelTag = 5102
    private let aiProjectTag = 5103
    private let aiSessionTag = 5104
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
        databaseManager.initialize()
        startReasonixHook()
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

        // ── Token 用量（一级 + 详情入口） ──
        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem(title: "Token: — | 花费: —", symbol: "chart.bar.fill", tag: tokenSummaryTag, isEnabled: false))

        // ── 历史用量（二级菜单） ──
        menu.addItem(NSMenuItem.separator())
        buildTokenHistorySubmenu()
        let historyItem = menuItem(title: "历史用量", symbol: "calendar.badge.clock")
        historyItem.submenu = tokenHistorySubmenu
        menu.addItem(historyItem)

        // ── AI 分析（多子菜单） ──
        menu.addItem(NSMenuItem.separator())
        buildAiAnalysisSubmenu()
        let aiItem = menuItem(title: "AI 分析", symbol: "brain.head.profile")
        aiItem.submenu = aiAnalysisSubmenu
        menu.addItem(aiItem)

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

        // ── 更新流量汇总子菜单
        updateDailyTraffic()
        updateTrafficSubmenu()

        // 更新 Token 一级项目
        updateTokenSubmenu()

        // 更新 AI 分析子菜单
        updateAiAnalysisSubmenu()

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

    // MARK: - Reasonix Hook

    /// 启动 Reasonix Hook 事件监听器
    private func startReasonixHook() {
        let hookMonitor = ReasonixHookMonitor(database: databaseManager)
        hookMonitor.start()
        reasonixHookMonitor = hookMonitor
        print("📡 Reasonix Hook 监听器已启动")
    }

    // MARK: - Token 用量（一级 + 历史二级菜单）

    /// 更新 Token 一级项目 + 每小时明细 + 历史子菜单
    private func updateTokenSubmenu() {
        let total = tokenUsageProvider.fetchTodayTotal()
        guard let menu = statusItem.menu else { return }

        // 一级：Token 总数 + 花费
        if let item = menu.item(withTag: tokenSummaryTag) {
            item.title = "Token: \(Self.formatTokenShort(total.tokens)) | 花费: \(Self.formatCostShort(total.cost))"
        }

        // 一级：每小时明细（动态插入）
        updateTokenHourlyItems(in: menu)

        // 二级：历史用量
        updateTokenHistorySubmenu()
    }

    /// 在一级菜单中插入每小时迷你图表
    private func updateTokenHourlyItems(in menu: NSMenu) {
        let hourly = tokenUsageProvider.fetchHourlyBreakdown()
        let hash = hourly.map { "\($0.hour):\($0.totalTokens)" }.joined(separator: ",")
        guard hash != lastHourlyHash else { return }
        lastHourlyHash = hash

        // 移除旧的每小时条目（tag 从 tokenHourBaseTag 开始）
        var idx = menu.numberOfItems - 1
        while idx >= 0 {
            if let item = menu.item(at: idx), item.tag >= tokenHourBaseTag {
                menu.removeItem(at: idx)
            }
            idx -= 1
        }

        guard hourly.contains(where: { $0.totalTokens > 0 }) else { return }

        // 找到历史用量前面的位置
        var insertIdx = 0
        for i in 0..<menu.numberOfItems {
            if let item = menu.item(at: i), item.submenu === tokenHistorySubmenu {
                insertIdx = i
                break
            }
        }

        // 创建迷你柱状图作为单个菜单项
        let chartView = MiniMenuChartView(data: hourly)
        chartView.frame = NSRect(x: 0, y: 0, width: 260, height: 80)

        let chartItem = NSMenuItem()
        chartItem.view = chartView
        chartItem.tag = tokenHourBaseTag
        chartItem.isEnabled = false
        menu.insertItem(chartItem, at: insertIdx)
    }

    /// 构建历史用量子菜单
    private func buildTokenHistorySubmenu() {
        tokenHistorySubmenu.removeAllItems()
        tokenHistorySubmenu.addItem(menuItem(title: "加载中…", symbol: "calendar", isEnabled: false))
    }

    /// 更新历史用量子菜单（内嵌图表）
    private func updateTokenHistorySubmenu() {
        let history = tokenUsageProvider.fetchDailyHistory(days: 7)
        let hash = history.map { "\($0.date):\($0.totalTokens)" }.joined(separator: ",")
        guard hash != lastHistoryHash else { return }
        lastHistoryHash = hash

        tokenHistorySubmenu.removeAllItems()

        if history.isEmpty {
            tokenHistorySubmenu.addItem(menuItem(title: "暂无数据", symbol: "calendar", isEnabled: false))
            return
        }

        let chartView = MiniHistoryMenuChartView(data: history)
        chartView.frame = NSRect(x: 0, y: 0, width: 260, height: 100)

        let item = NSMenuItem()
        item.view = chartView
        item.isEnabled = false
        tokenHistorySubmenu.addItem(item)
    }

    // MARK: - AI 分析子菜单

    /// 构建 AI 分析子菜单结构
    private func buildAiAnalysisSubmenu() {
        aiAnalysisSubmenu.removeAllItems()

        aiAnalysisSubmenu.addItem(menuItem(title: "AI 实时动态", symbol: "antenna.radiowaves.left.and.right",
                                           tag: aiDynamicTag))
        aiAnalysisSubmenu.item(withTag: aiDynamicTag)?.submenu = aiDynamicSubmenu

        aiAnalysisSubmenu.addItem(menuItem(title: "AI 工具统计", symbol: "wrench.adjustable",
                                           tag: aiToolStatsTag))
        aiAnalysisSubmenu.item(withTag: aiToolStatsTag)?.submenu = aiToolStatsSubmenu

        aiAnalysisSubmenu.addItem(menuItem(title: "AI 模型统计", symbol: "cpu",
                                           tag: aiModelTag))
        aiAnalysisSubmenu.item(withTag: aiModelTag)?.submenu = aiModelSubmenu

        aiAnalysisSubmenu.addItem(menuItem(title: "AI 项目统计", symbol: "folder",
                                           tag: aiProjectTag))
        aiAnalysisSubmenu.item(withTag: aiProjectTag)?.submenu = aiProjectSubmenu

        aiAnalysisSubmenu.addItem(NSMenuItem.separator())
        aiAnalysisSubmenu.addItem(menuItem(title: "AI 会话统计: —", symbol: "chart.pie",
                                           tag: aiSessionTag, isEnabled: false))

        // 填充占位
        aiDynamicSubmenu.addItem(menuItem(title: "加载中…", isEnabled: false))
        aiToolStatsSubmenu.addItem(menuItem(title: "加载中…", isEnabled: false))
        aiModelSubmenu.addItem(menuItem(title: "加载中…", isEnabled: false))
        aiProjectSubmenu.addItem(menuItem(title: "加载中…", isEnabled: false))
    }

    /// 更新 AI 分析子菜单
    private func updateAiAnalysisSubmenu() {
        updateAiDynamicSubmenu()
        updateAiToolStatsSubmenu()
        updateAiModelSubmenu()
        updateAiProjectSubmenu()
        updateAiSessionStatsItem()
    }

    /// 更新实时动态子菜单
    private func updateAiDynamicSubmenu() {
        let calls = tokenUsageProvider.fetchRecentToolCalls(limit: 8)
        aiDynamicSubmenu.removeAllItems()

        if calls.isEmpty {
            aiDynamicSubmenu.addItem(menuItem(title: "暂无工具调用", isEnabled: false))
            return
        }

        for call in calls {
            let statusIcon = call.status == "success" ? "✅" : (call.status == "failure" ? "❌" : "⏳")
            let timeStr = call.secondsAgo < 60 ? "\(call.secondsAgo)s前" : "\(call.secondsAgo / 60)m前"
            let durStr = call.durationMs > 0 ? " \(call.durationMs)ms" : ""
            let title = "\(statusIcon) \(call.toolName)  (\(timeStr))\(durStr)"
            let item = menuItem(title: title, isEnabled: false)
            aiDynamicSubmenu.addItem(item)
        }
    }

    /// 更新工具统计子菜单
    private func updateAiToolStatsSubmenu() {
        let stats = tokenUsageProvider.fetchToolCallRanking(limit: 6)
        aiToolStatsSubmenu.removeAllItems()

        if stats.isEmpty {
            aiToolStatsSubmenu.addItem(menuItem(title: "暂无工具数据", isEnabled: false))
            return
        }

        for s in stats {
            let rateStr = String(format: "%.0f%%", s.successRate)
            let durStr = s.avgDurationMs > 0 ? " ⏱\(s.avgDurationMs)ms" : ""
            let title = "\(s.toolName)  \(s.callCount)次  ✅\(rateStr)\(durStr)"
            aiToolStatsSubmenu.addItem(menuItem(title: title, isEnabled: false))
        }
    }

    /// 更新模型统计子菜单
    private func updateAiModelSubmenu() {
        let models = tokenUsageProvider.fetchModelRanking(limit: 5)
        aiModelSubmenu.removeAllItems()

        if models.isEmpty {
            aiModelSubmenu.addItem(menuItem(title: "暂无模型数据", isEnabled: false))
            return
        }

        for m in models {
            let tokensStr = Self.formatTokenShort(m.totalTokens)
            let costStr = Self.formatCostShort(m.totalCost)
            let title = "\(m.model)  \(tokensStr)Token  \(costStr)"
            aiModelSubmenu.addItem(menuItem(title: title, isEnabled: false))
        }
    }

    /// 更新项目统计子菜单
    private func updateAiProjectSubmenu() {
        let projects = tokenUsageProvider.fetchProjectRanking(limit: 5)
        aiProjectSubmenu.removeAllItems()

        if projects.isEmpty {
            aiProjectSubmenu.addItem(menuItem(title: "暂无项目数据", isEnabled: false))
            return
        }

        for p in projects {
            let tokensStr = Self.formatTokenShort(p.totalTokens)
            let costStr = Self.formatCostShort(p.totalCost)
            let title = "\(p.project)  \(tokensStr)Token  \(p.sessionCount)会话  \(costStr)"
            aiProjectSubmenu.addItem(menuItem(title: title, isEnabled: false))
        }
    }

    /// 更新会话统计概览项
    private func updateAiSessionStatsItem() {
        let stats = tokenUsageProvider.fetchSessionOverviewStats()
        let failStr = String(format: "%.0f%%", stats.failRate)
        let ratioStr = String(format: "%.0f%%", stats.reasoningTokenRatio)
        let title = "AI 会话统计: 活跃\(stats.activeSessions) | 今日\(stats.todayTotal) | 失败率\(failStr) | 推理\(ratioStr)"
        if let item = aiAnalysisSubmenu.item(withTag: aiSessionTag) {
            item.title = title
        }
    }

    // MARK: - 格式化辅助（菜单栏共用）

    /// 短格式 Token 数（中文单位）
    nonisolated static func formatTokenShort(_ count: Int) -> String {
        if count >= 100_000_000 {
            return String(format: "%.1f亿", Double(count) / 100_000_000)
        }
        if count >= 10_000 {
            return String(format: "%.1f万", Double(count) / 10_000)
        }
        return "\(count)"
    }

    /// 短格式花费
    nonisolated static func formatCostShort(_ cost: Double) -> String {
        if cost < 0.01 { return String(format: "¥%.4f", cost) }
        if cost < 1 { return String(format: "¥%.3f", cost) }
        return String(format: "¥%.2f", cost)
    }

    /// 短格式日期 "7/25"
    private static func formatDateShort(_ dateStr: String) -> String {
        let parts = dateStr.split(separator: "-")
        guard parts.count == 3 else { return dateStr }
        return "\(Int(parts[1])!)/\(Int(parts[2])!)"
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
