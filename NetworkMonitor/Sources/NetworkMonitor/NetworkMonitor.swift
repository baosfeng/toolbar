import AppKit
import Darwin
import NetworkMonitorCore

// MARK: - Network Speed Monitor

/// Monitors network interface byte counters and computes upload/download speeds.
@MainActor
final class NetworkSpeedMonitor {
    private var previousData: [String: (rx: UInt64, tx: UInt64)] = [:]
    private var previousTimestamp: Date = Date()

    /// Current download speed in bytes per second.
    private(set) var downloadSpeed: Double = 0
    /// Current upload speed in bytes per second.
    private(set) var uploadSpeed: Double = 0
    /// Total bytes received since app launch.
    private(set) var totalRx: UInt64 = 0
    /// Total bytes sent since app launch.
    private(set) var totalTx: UInt64 = 0

    /// Polls the latest speeds. Call this periodically (e.g., every 1s).
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

    /// Reads bytes received/sent for all active non-loopback interfaces using getifaddrs.
    private func readInterfaceBytes() -> [String: (rx: UInt64, tx: UInt64)] {
        var result: [String: (rx: UInt64, tx: UInt64)] = [:]

        var ifaddr: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else {
            return result
        }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let current = ptr {
            let name = String(cString: current.pointee.ifa_name)
            // Skip loopback
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

/// Tracks per-process network usage by polling `nettop` and computing deltas.
@MainActor
final class ProcessNetworkMonitor {
    /// Previous cumulative snapshot: pid → (bytesIn, bytesOut)
    private var previous: [Int32: (UInt64, UInt64)] = [:]

    /// Current process speeds: pid → (downloadSpeed, uploadSpeed) in B/s
    private(set) var processSpeeds: [ProcessNetUsage] = []

    /// Time of last successful update.
    private var lastUpdateTime: Date?

    /// Fetch latest snapshot and compute deltas. Should be called every ~1s.
    func poll() {
        guard let snapshot = try? runNettopSnapshot(), !snapshot.isEmpty else {
            return
        }

        let now = Date()
        let elapsed: Double
        if let last = lastUpdateTime {
            elapsed = now.timeIntervalSince(last)
        } else {
            elapsed = 1.0  // assume 1s on first run
        }
        lastUpdateTime = now

        var speeds: [ProcessNetUsage] = []

        for current in snapshot {
            if let prev = previous[current.pid] {
                let deltaIn = current.bytesIn >= prev.0 ? current.bytesIn - prev.0 : current.bytesIn
                let deltaOut = current.bytesOut >= prev.1 ? current.bytesOut - prev.1 : current.bytesOut
                let speedIn = Double(deltaIn) / elapsed
                let speedOut = Double(deltaOut) / elapsed
                // Only include processes with non-zero activity
                if speedIn > 0 || speedOut > 0 {
                    speeds.append(ProcessNetUsage(
                        name: current.name,
                        pid: current.pid,
                        bytesIn: UInt64(speedIn),
                        bytesOut: UInt64(speedOut)
                    ))
                }
            }
            previous[current.pid] = (current.bytesIn, current.bytesOut)
        }

        // Sort by total bytes (descending)
        speeds.sort(by: { $0.total > $1.total })
        processSpeeds = speeds
    }
}

// MARK: - Two-Line Label View

/// A simple view with two labels: upload on top, download below.
/// Attached as a subview of the status item button so the button handles clicks natively.
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

    /// Tags for dynamic process menu items.
    private let processSectionTag: Int = 2000
    private let maxProcessItems: Int = 10

    private let formatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .decimal
        f.includesUnit = true
        f.includesCount = true
        f.allowedUnits = [.useAll]
        f.isAdaptive = true
        return f
    }()

    override init() {
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
    }

    private func setupMenu() {
        let menu = NSMenu()

        let headerItem = NSMenuItem(title: "网络监控", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        menu.addItem(NSMenuItem.separator())

        let detailsItem = NSMenuItem(title: "▼ 0 KB/s  ▲ 0 KB/s", action: nil, keyEquivalent: "")
        detailsItem.isEnabled = false
        detailsItem.tag = 1001
        menu.addItem(detailsItem)

        menu.addItem(NSMenuItem.separator())

        // Process list header
        let procHeader = NSMenuItem(title: "活跃进程", action: nil, keyEquivalent: "")
        procHeader.isEnabled = false
        procHeader.tag = processSectionTag
        menu.addItem(procHeader)

        // Dynamic process items will go here (tags processSectionTag+1 ...)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
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
        // Interface-level speed
        monitor.poll()
        let downSpeed = max(monitor.downloadSpeed, 0)
        let upSpeed = max(monitor.uploadSpeed, 0)
        let downStr = formatSpeedShort(downSpeed)
        let upStr = formatSpeedShort(upSpeed)

        // Update status bar display
        labelView.setSpeeds(upload: upStr, download: downStr)

        // Per-process speed
        processMonitor.poll()
        let processes = processMonitor.processSpeeds

        // Update menu items
        guard let menu = statusItem.menu else { return }

        // Update detail item
        if let detailsItem = menu.item(withTag: 1001) {
            let downFull = formatter.string(fromByteCount: Int64(downSpeed)) + "/s"
            let upFull = formatter.string(fromByteCount: Int64(upSpeed)) + "/s"
            detailsItem.title = "▼ \(downFull)  ▲ \(upFull)"
        }

        // Update header total
        if let headerItem = menu.item(at: 0) {
            let totalDown = formatter.string(fromByteCount: Int64(monitor.totalRx))
            let totalUp = formatter.string(fromByteCount: Int64(monitor.totalTx))
            headerItem.title = "总计：↓\(totalDown)  ↑\(totalUp)"
        }

        // Rebuild process items
        updateProcessItems(menu: menu, processes: processes)
    }

    /// Remove old process items and insert new ones sorted by traffic (descending).
    private func updateProcessItems(menu: NSMenu, processes: [ProcessNetUsage]) {
        // Remove old process items (everything between process header and last separator)
        while let item = menu.item(withTag: processSectionTag + 1) {
            menu.removeItem(item)
        }

        // Insert new items (up to maxProcessItems)
        let top = processes.prefix(maxProcessItems)
        for process in top {
            let downStr = formatSpeedShort(Double(process.bytesIn))
            let upStr = formatSpeedShort(Double(process.bytesOut))
            let title = "\(process.name)  ▼\(downStr)  ▲\(upStr)"
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.tag = processSectionTag + 1  // will be removed next cycle
            // Insert after the process header
            let headerIndex = menu.indexOfItem(withTag: processSectionTag)
            if headerIndex >= 0 {
                menu.insertItem(item, at: headerIndex + 1)
            }
        }

        // If no processes, show a note
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

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    nonisolated deinit {
        // Timer will be cleaned up by the OS when the object is deallocated
    }
}

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarManager: MenuBarManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarManager = MenuBarManager()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Clean up
    }
}
