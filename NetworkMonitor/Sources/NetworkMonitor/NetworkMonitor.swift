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
    private var timer: Timer?

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

    /// Attach the label view to the button.
    /// The button handles clicks and shows the menu natively.
    private func setupButton() {
        guard let button = statusItem.button else { return }
        button.title = ""  // Clear default text
        button.addSubview(labelView)

        // Constrain labelView to fill the button
        NSLayoutConstraint.activate([
            labelView.topAnchor.constraint(equalTo: button.topAnchor),
            labelView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            labelView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            labelView.bottomAnchor.constraint(equalTo: button.bottomAnchor),
        ])
    }

    private func setupMenu() {
        let menu = NSMenu()

        let headerItem = NSMenuItem(title: "Network Monitor", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        menu.addItem(NSMenuItem.separator())

        let detailsItem = NSMenuItem(title: "▼ 0 KB/s  ▲ 0 KB/s", action: nil, keyEquivalent: "")
        detailsItem.isEnabled = false
        detailsItem.tag = 1001
        menu.addItem(detailsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
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
        monitor.poll()

        let downSpeed = max(monitor.downloadSpeed, 0)
        let upSpeed = max(monitor.uploadSpeed, 0)

        let downStr = formatSpeedShort(downSpeed)
        let upStr = formatSpeedShort(upSpeed)

        // Update the two-line display: upload on top, download below
        labelView.setSpeeds(upload: upStr, download: downStr)

        // Update dropdown detail menu items
        guard let menu = statusItem.menu else { return }

        if let detailsItem = menu.item(withTag: 1001) {
            let downFull = formatter.string(fromByteCount: Int64(downSpeed)) + "/s"
            let upFull = formatter.string(fromByteCount: Int64(upSpeed)) + "/s"
            detailsItem.title = "▼ \(downFull)  ▲ \(upFull)"
        }

        if let headerItem = menu.item(at: 0) {
            let totalDown = formatter.string(fromByteCount: Int64(monitor.totalRx))
            let totalUp = formatter.string(fromByteCount: Int64(monitor.totalTx))
            headerItem.title = "Total: ↓\(totalDown)  ↑\(totalUp)"
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
