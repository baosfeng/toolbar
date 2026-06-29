import AppKit
import Darwin
import ServiceManagement
import NetworkMonitorCore

// MARK: - Network Speed Monitor

@MainActor
final class NetworkSpeedMonitor {
    private var previousData: [String: (rx: UInt64, tx: UInt64)] = [:]
    private var previousTimestamp: Date = Date()

    private(set) var downloadSpeed: Double = 0
    private(set) var uploadSpeed: Double = 0
    private(set) var totalRx: UInt64 = 0
    private(set) var totalTx: UInt64 = 0

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
    }
}

// MARK: - Two-Line Label View

@MainActor
final class DualLabelView: NSView {
    let uploadLabel = NSTextField(labelWithString: "▲ 0")
    let downloadLabel = NSTextField(labelWithString: "▼ 0")

    override var intrinsicContentSize: NSSize {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        let sample = "▲ 1.2G" as NSString
        let textWidth = sample.size(withAttributes: [.font: font]).width
        let width = ceil(textWidth) + 12
        let lineHeight = font.leading + font.capHeight + font.descender + 3
        let height = ceil(lineHeight * 2) + 4
        return NSSize(width: width, height: height)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        let font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        for label in [uploadLabel, downloadLabel] {
            label.font = font
            label.textColor = .labelColor
            label.alignment = .center
            label.isBezeled = false
            label.isEditable = false
            label.drawsBackground = false
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
        }
        NSLayoutConstraint.activate([
            uploadLabel.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            uploadLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            uploadLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            downloadLabel.topAnchor.constraint(equalTo: uploadLabel.bottomAnchor, constant: -2),
            downloadLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            downloadLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            downloadLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
        ])
    }

    func setSpeeds(upload: String, download: String) {
        uploadLabel.stringValue = "▲ \(upload)"
        downloadLabel.stringValue = "▼ \(download)"
        invalidateIntrinsicContentSize()
    }
}

// MARK: - Menu Bar Manager

@MainActor
final class MenuBarManager: NSObject {
    private let statusItem: NSStatusItem
    private let labelView = DualLabelView()
    private let monitor = NetworkSpeedMonitor()
    private let processMonitor = ProcessNetworkMonitor()
    private var timer: Timer?

    private let processSectionTag: Int = 2000
    private let launchAtStartupTag: Int = 3001
    private let maxProcessItems: Int = 10

    /// UserDefaults key for launch-at-startup preference.
    private static let launchPrefKey = "launchAtStartup"

    /// Trend history (last 60 seconds)
    private var downHistory: [Double] = []
    private var upHistory: [Double] = []
    private let maxHistory: Int = 60

    /// Log entries for export
    private var logEntries: [NetworkLogEntry] = []

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        setupButton()
        setupMenu()
        restoreLaunchAtStartup()
        setupTimer()
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
    }

    private func setupMenu() {
        let menu = NSMenu()

        let headerItem = NSMenuItem(title: "网络监控", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        let ipItem = NSMenuItem(title: "IP: 获取中…", action: nil, keyEquivalent: "")
        ipItem.isEnabled = false
        ipItem.tag = 1002
        menu.addItem(ipItem)

        menu.addItem(NSMenuItem.separator())

        let detailsItem = NSMenuItem(title: "▼ 0 KB/s  ▲ 0 KB/s", action: nil, keyEquivalent: "")
        detailsItem.isEnabled = false
        detailsItem.tag = 1001
        menu.addItem(detailsItem)

        // Trend mini-chart
        let trendItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        trendItem.isEnabled = false
        trendItem.tag = 1003
        menu.addItem(trendItem)

        menu.addItem(NSMenuItem.separator())

        // Process list header
        let procHeader = NSMenuItem(title: "活跃进程", action: nil, keyEquivalent: "")
        procHeader.isEnabled = false
        procHeader.tag = processSectionTag
        menu.addItem(procHeader)

        menu.addItem(NSMenuItem.separator())

        // Copy info
        let copyItem = NSMenuItem(title: "复制网络信息", action: #selector(copyNetworkInfo), keyEquivalent: "c")
        copyItem.target = self
        menu.addItem(copyItem)

        // Export log
        let exportItem = NSMenuItem(title: "导出流量日志…", action: #selector(exportLog), keyEquivalent: "e")
        exportItem.target = self
        menu.addItem(exportItem)

        menu.addItem(NSMenuItem.separator())

        let launchItem = NSMenuItem(title: "开机自启动", action: #selector(toggleLaunchAtStartup), keyEquivalent: "")
        launchItem.target = self
        launchItem.tag = launchAtStartupTag
        menu.addItem(launchItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu

        if let launchItem = menu.item(withTag: launchAtStartupTag) {
            launchItem.state = isLaunchAtStartupEnabled ? .on : .off
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

    @objc private func update() {
        monitor.poll()
        let downSpeed = max(monitor.downloadSpeed, 0)
        let upSpeed = max(monitor.uploadSpeed, 0)
        let downStr = formatSpeedShort(downSpeed)
        let upStr = formatSpeedShort(upSpeed)

        labelView.setSpeeds(upload: upStr, download: downStr)

        // Trend history
        downHistory.append(downSpeed)
        upHistory.append(upSpeed)
        if downHistory.count > maxHistory { downHistory.removeFirst() }
        if upHistory.count > maxHistory { upHistory.removeFirst() }

        // Log every 5 seconds to keep file size manageable
        let shouldLog = logEntries.isEmpty || Date().timeIntervalSince(logEntries.last!.timestamp) >= 5
        if shouldLog {
            logEntries.append(NetworkLogEntry(
                timestamp: Date(),
                downSpeed: downSpeed,
                upSpeed: upSpeed,
                totalRx: monitor.totalRx,
                totalTx: monitor.totalTx,
                ip: getLocalIPAddress()
            ))
        }

        // Per-process
        processMonitor.poll()
        let processes = processMonitor.processSpeeds

        guard let menu = statusItem.menu else { return }

        // Launch-at-startup
        if let launchItem = menu.item(withTag: launchAtStartupTag) {
            launchItem.state = isLaunchAtStartupEnabled ? .on : .off
        }

        // IP address
        if let ipItem = menu.item(withTag: 1002) {
            if let ip = getLocalIPAddress() {
                ipItem.title = "IP: \(ip)"
            } else {
                ipItem.title = "IP: 未连接"
            }
        }

        // Detail item
        if let detailsItem = menu.item(withTag: 1001) {
            let downFull = formatBytesFull(UInt64(downSpeed)) + "/s"
            let upFull = formatBytesFull(UInt64(upSpeed)) + "/s"
            detailsItem.title = "▼ \(downFull)  ▲ \(upFull)"
        }

        // Trend sparkline
        if let trendItem = menu.item(withTag: 1003) {
            let totalHistory = zip(downHistory, upHistory).map { $0 + $1 }
            if !totalHistory.isEmpty {
                let line = sparkline(from: totalHistory)
                trendItem.title = "趋势  \(line)"
            }
        }

        // Header total
        if let headerItem = menu.item(at: 0) {
            let totalDown = formatBytesFull(monitor.totalRx)
            let totalUp = formatBytesFull(monitor.totalTx)
            headerItem.title = "总计：↓\(totalDown)  ↑\(totalUp)"
        }

        updateProcessItems(menu: menu, processes: processes)
    }

    private func updateProcessItems(menu: NSMenu, processes: [ProcessNetUsage]) {
        while let item = menu.item(withTag: processSectionTag + 1) {
            menu.removeItem(item)
        }

        let top = processes.prefix(maxProcessItems)
        for process in top {
            let downStr = formatSpeedShort(Double(process.bytesIn))
            let upStr = formatSpeedShort(Double(process.bytesOut))
            let title = "\(process.name)  ▼\(downStr)  ▲\(upStr)"
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.tag = processSectionTag + 1
            let headerIndex = menu.indexOfItem(withTag: processSectionTag)
            if headerIndex >= 0 {
                menu.insertItem(item, at: headerIndex + 1)
            }
        }

        if top.isEmpty {
            let item = NSMenuItem(title: "（暂无活跃流量）", action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.tag = processSectionTag + 1
            let headerIdx = menu.indexOfItem(withTag: processSectionTag)
            if headerIdx >= 0 {
                menu.insertItem(item, at: headerIdx + 1)
            }
        }
    }

    // MARK: - Actions

    @objc private func copyNetworkInfo() {
        let ip = getLocalIPAddress() ?? "未连接"
        let down = formatBytesFull(UInt64(monitor.downloadSpeed)) + "/s"
        let up = formatBytesFull(UInt64(monitor.uploadSpeed)) + "/s"
        let totalDown = formatBytesFull(monitor.totalRx)
        let totalUp = formatBytesFull(monitor.totalTx)

        let text = """
        网络监控
        IP: \(ip)
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

    private var isLaunchAtStartupEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// On first launch, re-register if the user had previously enabled this.
    private func restoreLaunchAtStartup() {
        guard UserDefaults.standard.bool(forKey: Self.launchPrefKey) else { return }
        if SMAppService.mainApp.status != .enabled {
            try? SMAppService.mainApp.register()
        }
        if let item = statusItem.menu?.item(withTag: launchAtStartupTag) {
            item.state = isLaunchAtStartupEnabled ? .on : .off
        }
    }

    @objc private func toggleLaunchAtStartup() {
        do {
            if isLaunchAtStartupEnabled {
                try SMAppService.mainApp.unregister()
                UserDefaults.standard.set(false, forKey: Self.launchPrefKey)
            } else {
                try SMAppService.mainApp.register()
                UserDefaults.standard.set(true, forKey: Self.launchPrefKey)
            }
        } catch {
            print("Failed to toggle launch-at-startup: \(error)")
        }
        if let item = statusItem.menu?.item(withTag: launchAtStartupTag) {
            item.state = isLaunchAtStartupEnabled ? .on : .off
        }
    }

    nonisolated deinit {}
}

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarManager: MenuBarManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarManager = MenuBarManager()
    }

    func applicationWillTerminate(_ notification: Notification) {}
}
