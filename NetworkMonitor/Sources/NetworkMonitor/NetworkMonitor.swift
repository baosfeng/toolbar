import AppKit
import Darwin
import ServiceManagement
import CoreWLAN

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

        // Remove interfaces that are no longer active
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

        // Remove stale PIDs that are no longer in the snapshot
        let currentPids = Set(snapshot.map { $0.pid })
        previous = previous.filter { currentPids.contains($0.key) }
    }
}

// MARK: - Dual-Label Status Bar View

@MainActor
final class DualLabelView: NSView {
    private let uploadIconView = NSImageView()
    private let downloadIconView = NSImageView()
    private let uploadLabel: NSTextField = {
        let l = NSTextField(labelWithString: "0 B/s")
        l.textColor = .systemOrange
        return l
    }()
    private let downloadLabel: NSTextField = {
        let l = NSTextField(labelWithString: "0 B/s")
        l.textColor = .systemGreen
        return l
    }()

    override var intrinsicContentSize: NSSize {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        let sample = "1.2 G/s" as NSString
        let textWidth = sample.size(withAttributes: [.font: font]).width
        let iconWidth: CGFloat = 10
        let totalWidth = ceil(textWidth) + iconWidth + 16
        let lineHeight = font.leading + font.capHeight + font.descender + 3
        let height = ceil(lineHeight * 2) + 6
        return NSSize(width: totalWidth, height: height)
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

        // Configure icon image views
        let iconConfig = NSImage.SymbolConfiguration(pointSize: 8, weight: .bold)
        if let downImg = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: "Download") {
            downloadIconView.image = downImg
            downloadIconView.contentTintColor = .systemGreen
            downloadIconView.symbolConfiguration = iconConfig
        }
        if let upImg = NSImage(systemSymbolName: "arrow.up.circle.fill", accessibilityDescription: "Upload") {
            uploadIconView.image = upImg
            uploadIconView.contentTintColor = .systemOrange
            uploadIconView.symbolConfiguration = iconConfig
        }

        for iconView in [downloadIconView, uploadIconView] {
            iconView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(iconView)
        }

        for label in [downloadLabel, uploadLabel] {
            label.font = font
            label.alignment = .left
            label.isBezeled = false
            label.isEditable = false
            label.drawsBackground = false
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
        }

        NSLayoutConstraint.activate([
            // Download row
            downloadIconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            downloadIconView.centerYAnchor.constraint(equalTo: downloadLabel.centerYAnchor),
            downloadIconView.widthAnchor.constraint(equalToConstant: 10),
            downloadIconView.heightAnchor.constraint(equalToConstant: 10),
            downloadLabel.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            downloadLabel.leadingAnchor.constraint(equalTo: downloadIconView.trailingAnchor, constant: 3),
            downloadLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),

            // Upload row
            uploadIconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            uploadIconView.centerYAnchor.constraint(equalTo: uploadLabel.centerYAnchor),
            uploadIconView.widthAnchor.constraint(equalToConstant: 10),
            uploadIconView.heightAnchor.constraint(equalToConstant: 10),
            uploadLabel.topAnchor.constraint(equalTo: downloadLabel.bottomAnchor, constant: -1),
            uploadLabel.leadingAnchor.constraint(equalTo: uploadIconView.trailingAnchor, constant: 3),
            uploadLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            uploadLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
        ])
    }

    func setSpeeds(upload: String, download: String) {
        downloadLabel.stringValue = "\(download)/s"
        uploadLabel.stringValue = "\(upload)/s"
        invalidateIntrinsicContentSize()
    }
}

// MARK: - Detail Panel

@MainActor
final class DetailPanel: NSPanel {
    // Speed display
    private let downSpeedLabel = NSTextField(labelWithString: "0 KB/s")
    private let upSpeedLabel = NSTextField(labelWithString: "0 KB/s")
    private let downIconView = NSImageView()
    private let upIconView = NSImageView()
    private let downCaption = NSTextField(labelWithString: "下载")
    private let upCaption = NSTextField(labelWithString: "上传")

    // Info rows
    private let ipIconView = NSImageView()
    private let ipLabel = NSTextField(labelWithString: "—")
    private let wifiIconView = NSImageView()
    private let wifiLabel = NSTextField(labelWithString: "—")
    private let totalIconView = NSImageView()
    private let totalLabel = NSTextField(labelWithString: "↓0 B  ↑0 B")

    // Process section
    private let processHeaderLabel = NSTextField(labelWithString: "活跃进程")
    private let processList = NSTextField(labelWithString: "")

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 400),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        title = "网络监控"
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false

        setupViews()
    }

    private func setupViews() {
        guard let content = contentView else { return }
        content.wantsLayer = true

        let bigFont = NSFont.monospacedDigitSystemFont(ofSize: 30, weight: .bold)
        let normalFont = NSFont.systemFont(ofSize: 13)
        let captionFont = NSFont.systemFont(ofSize: 10)
        let smallFont = NSFont.systemFont(ofSize: 11)
        let sectionFont = NSFont.systemFont(ofSize: 12, weight: .semibold)

        // ═══ Speed Section ═══
        let speedStack = NSStackView()
        speedStack.orientation = .horizontal
        speedStack.distribution = .fillEqually
        speedStack.spacing = 0
        speedStack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(speedStack)

        // Download side
        let downStack = NSStackView()
        downStack.orientation = .vertical
        downStack.alignment = .centerX
        downStack.spacing = 2
        downStack.translatesAutoresizingMaskIntoConstraints = false

        downIconView.translatesAutoresizingMaskIntoConstraints = false
        let downSymbolConfig = NSImage.SymbolConfiguration(pointSize: 18, weight: .bold)
        if let img = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: "Download") {
            downIconView.image = img
            downIconView.contentTintColor = .systemGreen
            downIconView.symbolConfiguration = downSymbolConfig
        }
        downIconView.widthAnchor.constraint(equalToConstant: 22).isActive = true
        downIconView.heightAnchor.constraint(equalToConstant: 22).isActive = true

        downSpeedLabel.font = bigFont
        downSpeedLabel.textColor = .systemGreen
        downSpeedLabel.alignment = .center
        downSpeedLabel.isBezeled = false
        downSpeedLabel.isEditable = false
        downSpeedLabel.drawsBackground = false

        downCaption.font = captionFont
        downCaption.textColor = .secondaryLabelColor
        downCaption.alignment = .center
        downCaption.isBezeled = false
        downCaption.isEditable = false
        downCaption.drawsBackground = false

        downStack.addArrangedSubview(downIconView)
        downStack.addArrangedSubview(downSpeedLabel)
        downStack.addArrangedSubview(downCaption)
        speedStack.addArrangedSubview(downStack)

        // Upload side
        let upStack = NSStackView()
        upStack.orientation = .vertical
        upStack.alignment = .centerX
        upStack.spacing = 2
        upStack.translatesAutoresizingMaskIntoConstraints = false

        upIconView.translatesAutoresizingMaskIntoConstraints = false
        let upSymbolConfig = NSImage.SymbolConfiguration(pointSize: 18, weight: .bold)
        if let img = NSImage(systemSymbolName: "arrow.up.circle.fill", accessibilityDescription: "Upload") {
            upIconView.image = img
            upIconView.contentTintColor = .systemOrange
            upIconView.symbolConfiguration = upSymbolConfig
        }
        upIconView.widthAnchor.constraint(equalToConstant: 22).isActive = true
        upIconView.heightAnchor.constraint(equalToConstant: 22).isActive = true

        upSpeedLabel.font = bigFont
        upSpeedLabel.textColor = .systemOrange
        upSpeedLabel.alignment = .center
        upSpeedLabel.isBezeled = false
        upSpeedLabel.isEditable = false
        upSpeedLabel.drawsBackground = false

        upCaption.font = captionFont
        upCaption.textColor = .secondaryLabelColor
        upCaption.alignment = .center
        upCaption.isBezeled = false
        upCaption.isEditable = false
        upCaption.drawsBackground = false

        upStack.addArrangedSubview(upIconView)
        upStack.addArrangedSubview(upSpeedLabel)
        upStack.addArrangedSubview(upCaption)
        speedStack.addArrangedSubview(upStack)

        // ═══ Separator ═══
        let separator1 = NSBox()
        separator1.boxType = .separator
        separator1.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(separator1)

        // ═══ Info Section ═══
        let infoStack = NSStackView()
        infoStack.orientation = .vertical
        infoStack.spacing = 6
        infoStack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(infoStack)

        // Helper to create icon+label rows
        func makeInfoRow(iconView: NSImageView, symbolName: String, tint: NSColor, label: NSTextField) -> NSView {
            let row = NSView()
            row.translatesAutoresizingMaskIntoConstraints = false

            iconView.translatesAutoresizingMaskIntoConstraints = false
            if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
                iconView.image = img
                iconView.contentTintColor = tint
                iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
            }
            iconView.widthAnchor.constraint(equalToConstant: 18).isActive = true
            iconView.heightAnchor.constraint(equalToConstant: 18).isActive = true
            row.addSubview(iconView)

            label.font = normalFont
            label.textColor = .labelColor
            label.isBezeled = false
            label.isEditable = false
            label.drawsBackground = false
            label.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(label)

            NSLayoutConstraint.activate([
                iconView.leadingAnchor.constraint(equalTo: row.leadingAnchor),
                iconView.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
                label.trailingAnchor.constraint(equalTo: row.trailingAnchor),
                label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                row.heightAnchor.constraint(equalToConstant: 22),
            ])
            return row
        }

        infoStack.addArrangedSubview(makeInfoRow(iconView: ipIconView, symbolName: "network", tint: .systemBlue, label: ipLabel))
        infoStack.addArrangedSubview(makeInfoRow(iconView: wifiIconView, symbolName: "wifi", tint: .systemBlue, label: wifiLabel))
        infoStack.addArrangedSubview(makeInfoRow(iconView: totalIconView, symbolName: "arrow.down.arrow.up", tint: .secondaryLabelColor, label: totalLabel))

        // ═══ Separator ═══
        let separator2 = NSBox()
        separator2.boxType = .separator
        separator2.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(separator2)

        // ═══ Process Section ═══
        processHeaderLabel.font = sectionFont
        processHeaderLabel.textColor = .secondaryLabelColor
        processHeaderLabel.isBezeled = false
        processHeaderLabel.isEditable = false
        processHeaderLabel.drawsBackground = false
        processHeaderLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(processHeaderLabel)

        processList.font = smallFont
        processList.textColor = .labelColor
        processList.isBezeled = false
        processList.isEditable = false
        processList.drawsBackground = false
        processList.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(processList)

        // ═══ Layout Constraints ═══
        NSLayoutConstraint.activate([
            // Speed section
            speedStack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            speedStack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            speedStack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            speedStack.heightAnchor.constraint(equalToConstant: 90),

            // Separator 1
            separator1.topAnchor.constraint(equalTo: speedStack.bottomAnchor, constant: 16),
            separator1.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            separator1.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),

            // Info section
            infoStack.topAnchor.constraint(equalTo: separator1.bottomAnchor, constant: 12),
            infoStack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            infoStack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),

            // Separator 2
            separator2.topAnchor.constraint(equalTo: infoStack.bottomAnchor, constant: 12),
            separator2.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            separator2.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),

            // Process section
            processHeaderLabel.topAnchor.constraint(equalTo: separator2.bottomAnchor, constant: 10),
            processHeaderLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            processHeaderLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),

            processList.topAnchor.constraint(equalTo: processHeaderLabel.bottomAnchor, constant: 6),
            processList.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            processList.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            processList.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -16),
        ])
    }

    func update(downSpeed: Double, upSpeed: Double, totalRx: UInt64, totalTx: UInt64,
                ip: String?, wifi: String?, processes: [ProcessNetUsage]) {
        let downFull = formatBytesFull(UInt64(downSpeed)) + "/s"
        let upFull = formatBytesFull(UInt64(upSpeed)) + "/s"
        downSpeedLabel.stringValue = downFull
        upSpeedLabel.stringValue = upFull
        ipLabel.stringValue = ip ?? "未连接"
        wifiLabel.stringValue = wifi ?? "—"
        totalLabel.stringValue = "↓\(formatBytesFull(totalRx))  ↑\(formatBytesFull(totalTx))"

        // Top 15 processes
        let top = processes.prefix(15)
        if top.isEmpty {
            processList.stringValue = "暂无活跃流量"
            processList.textColor = .secondaryLabelColor
        } else {
            processList.textColor = .labelColor
            let lines = top.map { p -> String in
                "\(p.name)  ↓\(formatSpeedShort(Double(p.bytesIn)))  ↑\(formatSpeedShort(Double(p.bytesOut)))"
            }
            processList.stringValue = lines.joined(separator: "\n")
        }
    }
}

// MARK: - Menu Bar Manager

@MainActor
final class MenuBarManager: NSObject {
    private let statusItem: NSStatusItem
    private let labelView = DualLabelView()
    private var monitor: NetworkSpeedMonitor!
    private let processMonitor = ProcessNetworkMonitor()
    private var timer: Timer?
    private var detailPanel: DetailPanel?

    private let processSectionTag: Int = 2000
    private let launchAtStartupTag: Int = 3001
    private let maxProcessItems: Int = 10

    private static let launchPrefKey = "launchAtStartup"
    private static let totalRxKey = "totalRx"
    private static let totalTxKey = "totalTx"

    /// Get Wi-Fi name. Returns the SSID if CoreWLAN can access it,
    /// or "已连接" / "未连接" based on whether en0 has an IP address.
    private func getWiFiStatus() -> String {
        // Try CoreWLAN (requires entitlement + Location Services)
        if let ssid = CWWiFiClient.shared().interface()?.ssid(), !ssid.isEmpty {
            return ssid
        }
        // Fallback: check if en0 has an IP
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

        // Double-click opens detail panel
        let clickRecognizer = NSClickGestureRecognizer(target: self, action: #selector(toggleDetailPanel))
        clickRecognizer.numberOfClicksRequired = 2
        button.addGestureRecognizer(clickRecognizer)
    }

    /// Helper: create an NSMenuItem with an SF Symbol image
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
        let headerItem = NSMenuItem(title: "网络监控", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        // ── Network Status ──
        menu.addItem(menuItem(title: "IP: 获取中…", symbol: "network", tag: 1002, isEnabled: false))
        menu.addItem(menuItem(title: "Wi-Fi: —", symbol: "wifi", tag: 1004, isEnabled: false))

        menu.addItem(NSMenuItem.separator())

        // ── Speed Summary ──
        menu.addItem(menuItem(title: "▼ 0 KB/s  ▲ 0 KB/s", tag: 1001, isEnabled: false))
        menu.addItem(menuItem(title: "", tag: 1003, isEnabled: false))

        menu.addItem(NSMenuItem.separator())

        // ── Active Processes ──
        let procHeader = NSMenuItem(title: "活跃进程", action: nil, keyEquivalent: "")
        procHeader.isEnabled = false
        procHeader.tag = processSectionTag
        menu.addItem(procHeader)

        menu.addItem(NSMenuItem.separator())

        // ── Actions ──
        menu.addItem(menuItem(title: "打开详情面板", action: #selector(toggleDetailPanel), keyEquivalent: "d",
                              symbol: "info.circle.fill"))
        menu.addItem(menuItem(title: "复制网络信息", action: #selector(copyNetworkInfo), keyEquivalent: "c",
                              symbol: "doc.on.doc"))
        menu.addItem(menuItem(title: "导出流量日志…", action: #selector(exportLog), keyEquivalent: "e",
                              symbol: "square.and.arrow.up"))

        menu.addItem(NSMenuItem.separator())

        // ── Settings ──
        menu.addItem(menuItem(title: "开机自启动", action: #selector(toggleLaunchAtStartup),
                              symbol: "clock.arrow.circlepath", tag: launchAtStartupTag))

        menu.addItem(NSMenuItem.separator())

        // ── Quit ──
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

    @objc private func update() {
        monitor.poll()
        let downSpeed = max(monitor.downloadSpeed, 0)
        let upSpeed = max(monitor.uploadSpeed, 0)
        let downStr = formatSpeedShort(downSpeed)
        let upStr = formatSpeedShort(upSpeed)

        labelView.setSpeeds(upload: upStr, download: downStr)

        downHistory.append(downSpeed)
        upHistory.append(upSpeed)
        if downHistory.count > maxHistory { downHistory.removeFirst() }
        if upHistory.count > maxHistory { upHistory.removeFirst() }

        let shouldLog = logEntries.isEmpty || Date().timeIntervalSince(logEntries.last!.timestamp) >= 5
        if shouldLog {
            logEntries.append(NetworkLogEntry(
                timestamp: Date(),
                downSpeed: downSpeed, upSpeed: upSpeed,
                totalRx: monitor.totalRx, totalTx: monitor.totalTx,
                ip: getLocalIPAddress()
            ))
            // Keep at most 1000 entries (~1.4 hours of 5-second logging)
            if logEntries.count > 1000 {
                logEntries.removeFirst(logEntries.count - 1000)
            }
            // Persist cumulative totals every 5 seconds
            UserDefaults.standard.set(Int(monitor.totalRx), forKey: Self.totalRxKey)
            UserDefaults.standard.set(Int(monitor.totalTx), forKey: Self.totalTxKey)
        }

        processMonitor.poll()
        let processes = processMonitor.processSpeeds
        let ip = getLocalIPAddress()
        let wifi = getWiFiStatus()

        guard let menu = statusItem.menu else { return }

        if let launchItem = menu.item(withTag: launchAtStartupTag) {
            launchItem.state = isLaunchAtStartupSaved ? .on : .off
        }

        if let ipItem = menu.item(withTag: 1002) {
            ipItem.title = ip.map { "\($0)" } ?? "未连接"
        }

        if let wifiItem = menu.item(withTag: 1004) {
            wifiItem.title = "\(wifi)"
        }

        if let detailsItem = menu.item(withTag: 1001) {
            let downFull = formatBytesFull(UInt64(downSpeed)) + "/s"
            let upFull = formatBytesFull(UInt64(upSpeed)) + "/s"
            detailsItem.attributedTitle = nil
            detailsItem.title = "▼ \(downFull)    ▲ \(upFull)"
            // Color the speed string
            let attrStr = NSMutableAttributedString(string: detailsItem.title)
            let fullRange = NSRange(location: 0, length: attrStr.length)
            attrStr.addAttribute(.font, value: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular), range: fullRange)
            detailsItem.attributedTitle = attrStr
        }

        if let trendItem = menu.item(withTag: 1003) {
            let totalHistory = zip(downHistory, upHistory).map { $0 + $1 }
            if !totalHistory.isEmpty {
                let spark = sparkline(from: totalHistory, maxChars: 10)
                trendItem.title = "\(spark)"
            }
        }

        if let headerItem = menu.item(at: 0) {
            let totalDown = formatBytesFull(monitor.totalRx)
            let totalUp = formatBytesFull(monitor.totalTx)
            let attrStr = NSMutableAttributedString(string: "↓\(totalDown)  ↑\(totalUp)")
            let fullRange = NSRange(location: 0, length: attrStr.length)
            attrStr.addAttribute(.font, value: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium), range: fullRange)
            headerItem.attributedTitle = attrStr
        }

        updateProcessItems(menu: menu, processes: processes)

        // Update detail panel if open
        if let panel = detailPanel, panel.isVisible {
            panel.update(
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
            // Truncate process name to 14 chars so the line doesn't widen the menu
            let shortName = process.name.count > 14
                ? String(process.name.prefix(13)) + "…"
                : process.name
            let title = "  \(shortName)  ▼\(downStr)  ▲\(upStr)"

            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.tag = processSectionTag + 1

            // Add app icon if available
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

    /// Try to guess a bundle ID from a process name (best-effort for app icon lookup)
    private func guessBundleID(for processName: String) -> String {
        // Common mappings
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
        let ip = getLocalIPAddress() ?? "未连接"
        let wifi = getWiFiStatus()
        let down = formatBytesFull(UInt64(monitor.downloadSpeed)) + "/s"
        let up = formatBytesFull(UInt64(monitor.uploadSpeed)) + "/s"
        let totalDown = formatBytesFull(monitor.totalRx)
        let totalUp = formatBytesFull(monitor.totalTx)

        let text = """
        网络监控
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
        // 先更新配置文件，再操作系统登录项（即使 register 失败，配置也已记录）
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

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarManager: MenuBarManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarManager = MenuBarManager()
    }

    func applicationWillTerminate(_ notification: Notification) {}
}
