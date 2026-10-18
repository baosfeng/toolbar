import AppKit
import NetworkMonitorCore

// MARK: - 传送页行视图

// MARK: - 设备行

/// 设备行 — 在线状态点 + 名称 + 类型 + 配对标记
final class MenuPanelTransferDeviceRow: MenuPanelRow {

    private let statusDot = NSImageView()
    private let nameLabel: NSTextField
    private let detailLabel: NSTextField
    private var deviceId: String
    private var selectedDeviceId: String?

    init(device: RemoteDevice, selected: Bool) {
        nameLabel = MenuPanelLabel.text(device.alias, font: MenuPanelStyle.bodyFont)
        detailLabel = MenuPanelLabel.text(Self.detailText(device),
                                          font: MenuPanelStyle.sectionFont,
                                          color: MenuPanelStyle.secondaryText)
        deviceId = device.deviceId
        selectedDeviceId = selected ? device.deviceId : nil
        super.init(height: MenuPanelStyle.rowHeight, onClick: {})

        statusDot.translatesAutoresizingMaskIntoConstraints = false
        statusDot.imageScaling = .scaleProportionallyDown
        NSLayoutConstraint.activate([
            statusDot.widthAnchor.constraint(equalToConstant: 10),
            statusDot.heightAnchor.constraint(equalToConstant: 10),
        ])
        contentStack.addArrangedSubview(statusDot)
        contentStack.addArrangedSubview(nameLabel)
        contentStack.addArrangedSubview(MenuPanelLabel.spacer())
        detailLabel.setContentHuggingPriority(.required, for: .horizontal)
        contentStack.addArrangedSubview(detailLabel)
        applyStatus(device)
        setAccessibilityLabel("\(device.alias)，\(Self.detailText(device))")
    }

    func updateSelectedIndex(_ selectedId: String?) {
        selectedDeviceId = selectedId == deviceId ? deviceId : nil
        needsDisplay = true
    }

    private func applyStatus(_ device: RemoteDevice) {
        let symbol = device.isOnline ? "circle.fill" : "circle"
        let color = device.isOnline ? NSColor.systemGreen : NSColor.tertiaryLabelColor
        let config = NSImage.SymbolConfiguration(pointSize: 9, weight: .medium)
        statusDot.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        statusDot.contentTintColor = color
        nameLabel.textColor = device.isOnline ? .labelColor : MenuPanelStyle.secondaryText
        // 掉线：整体透明度 → 0.4（设计文档 §7.2）
        alphaValue = device.isOnline ? 1 : 0.4
    }

    private static func detailText(_ device: RemoteDevice) -> String {
        let type = device.deviceType == "android" ? "安卓" : "Mac"
        let paired = device.isPaired ? " · 已配对" : ""
        let online = device.isOnline ? "" : " · 离线"
        return "\(type)\(paired)\(online)"
    }

    /// 选中态：整行强调色底
    override func draw(_ dirtyRect: NSRect) {
        if selectedDeviceId != nil {
            MenuPanelStyle.accentColor.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 0, dy: 1), xRadius: 6, yRadius: 6).fill()
        }
        super.draw(dirtyRect)
    }
}

// MARK: - 任务行

/// 任务行 — 方向 + 文件名 + 状态 + 进度条（点击取消进行中的任务）
///
/// 动效：进度条 120ms 插值；完成显示对勾并弹入；失败整行抖动。
final class MenuPanelTransferTaskRow: MenuPanelRow {

    /// 是否允许点击（进行中才可取消）
    var onClickEnabled = true {
        didSet { onClick = onClickEnabled ? pendingAction : nil }
    }
    private var pendingAction: (() -> Void)?

    /// 右键菜单回调：true = 同时删除已落盘文件
    var onDismiss: ((_ deleteFiles: Bool) -> Void)?
    /// 仅已终结任务允许移除
    var allowsDismiss = false {
        didSet { needsDisplay = true }
    }

    /// 已终结任务提供右键菜单（移除记录 / 连带删除文件）
    override func menu(for event: NSEvent) -> NSMenu? {
        guard allowsDismiss, onDismiss != nil else { return nil }
        let menu = NSMenu()
        let record = NSMenuItem(title: "移除记录", action: #selector(handleDismissRecord), keyEquivalent: "")
        record.target = self
        menu.addItem(record)
        let withFiles = NSMenuItem(title: "移除记录并删除文件", action: #selector(handleDismissWithFiles), keyEquivalent: "")
        withFiles.target = self
        menu.addItem(withFiles)
        return menu
    }

    @objc private func handleDismissRecord() { onDismiss?(false) }
    @objc private func handleDismissWithFiles() { onDismiss?(true) }

    private let titleLabel: NSTextField
    private let stateLabel: NSTextField
    private let detailLabel: NSTextField
    private let track = MenuPanelTrackView(fillColor: .systemBlue)
    private let checkIcon = NSImageView()
    private var currentState: TransferState
    /// 速度采样（上次采样的已传字节与时间）
    private var lastSample: (bytes: Int64, at: Date)?
    private var lastSpeed: Double = 0

    init(session: TransferSession) {
        currentState = session.state
        lastSample = (session.totalTransferred, Date())
        titleLabel = MenuPanelLabel.text(Self.titleText(session), font: MenuPanelStyle.bodyFont)
        stateLabel = MenuPanelLabel.text(Self.stateText(session),
                                         font: MenuPanelStyle.sectionFont,
                                         color: Self.stateColor(session))
        detailLabel = MenuPanelLabel.text(Self.detailText(session, speed: 0),
                                          font: MenuPanelStyle.smallValueFont,
                                          color: MenuPanelStyle.secondaryText)
        super.init(height: 56, onClick: {})
        pendingAction = onClick

        titleLabel.lineBreakMode = .byTruncatingMiddle
        stateLabel.setContentHuggingPriority(.required, for: .horizontal)

        checkIcon.translatesAutoresizingMaskIntoConstraints = false
        checkIcon.image = NSImage(systemSymbolName: "checkmark.circle.fill",
                                  accessibilityDescription: "已完成")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold))
        checkIcon.contentTintColor = .systemGreen
        checkIcon.isHidden = session.state != .completed
        NSLayoutConstraint.activate([
            checkIcon.widthAnchor.constraint(equalToConstant: 14),
            checkIcon.heightAnchor.constraint(equalToConstant: 14),
        ])

        let topRow = NSStackView(views: [titleLabel, MenuPanelLabel.spacer(), checkIcon, stateLabel])
        topRow.orientation = .horizontal
        topRow.spacing = 6
        topRow.alignment = .centerY

        track.fraction = session.fraction
        track.fillColor = Self.stateColor(session)
        track.heightAnchor.constraint(equalToConstant: 4).isActive = true

        let vertical = NSStackView(views: [topRow, detailLabel, track])
        vertical.orientation = .vertical
        vertical.alignment = .leading
        vertical.spacing = 4
        vertical.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(vertical)
        vertical.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        setAccessibilityLabel("\(Self.titleText(session))，\(Self.stateText(session))")
    }

    /// 更新进度与状态（进度插值，状态迁移触发完成/失败动效）
    func update(session: TransferSession) {
        titleLabel.stringValue = Self.titleText(session)
        stateLabel.stringValue = Self.stateText(session)
        stateLabel.textColor = Self.stateColor(session)
        track.fillColor = Self.stateColor(session)
        let speed = measureSpeed(session: session)
        detailLabel.stringValue = Self.detailText(session, speed: speed)
        TransferMotion.animateProgress(track, to: session.fraction)

        guard session.state != currentState else { return }
        currentState = session.state
        switch session.state {
        case .completed:
            checkIcon.isHidden = false
            TransferMotion.checkmarkPop(checkIcon)
        case .failed:
            TransferMotion.shake(self)
        default:
            break
        }
    }

    /// 采样传输速度（0.2s 窗口；无新字节时保留上次值，避免数字跳 0）
    private func measureSpeed(session: TransferSession) -> Double {
        let now = Date()
        guard let sample = lastSample else {
            lastSample = (session.totalTransferred, now)
            return 0
        }
        let elapsed = now.timeIntervalSince(sample.at)
        guard elapsed >= 0.2 else { return lastSpeed }
        let delta = session.totalTransferred - sample.bytes
        lastSample = (session.totalTransferred, now)
        lastSpeed = delta > 0 && elapsed > 0 ? Double(delta) / elapsed : 0
        return lastSpeed
    }

    /// 详情行：传输中显示「已传 / 总量 · 速度」，其余显示总量
    private static func detailText(_ session: TransferSession, speed: Double) -> String {
        let total = formatBytesFull(UInt64(max(0, session.totalSize)))
        guard session.state == .transferring else { return total }
        let transferred = formatBytesFull(UInt64(max(0, session.totalTransferred)))
        guard speed > 0 else { return "\(transferred) / \(total)" }
        return "\(transferred) / \(total) · \(formatBytesFull(UInt64(speed)))/s"
    }

    private static func titleText(_ session: TransferSession) -> String {
        let direction = session.direction == .send ? "发送" : "接收"
        guard let first = session.files.first else { return "\(direction) 空会话" }
        if session.files.count == 1 { return "\(direction) \(first.name)" }
        return "\(direction) \(first.name) 等 \(session.files.count) 个文件"
    }

    private static func stateText(_ session: TransferSession) -> String {
        switch session.state {
        case .pending: return "准备中"
        case .offering: return "协商中"
        case .awaitingConfirm: return "等待确认"
        case .transferring:
            let percent = Int((session.fraction * 100).rounded())
            return "\(percent)%"
        case .verifying: return "校验中"
        case .completed: return "已完成"
        case .failed: return "失败"
        case .cancelled: return "已取消"
        }
    }

    private static func stateColor(_ session: TransferSession) -> NSColor {
        switch session.state {
        case .completed: return .systemGreen
        case .failed: return .systemRed
        case .cancelled: return MenuPanelStyle.secondaryText
        case .transferring, .verifying: return .systemBlue
        default: return MenuPanelStyle.secondaryText
        }
    }
}
