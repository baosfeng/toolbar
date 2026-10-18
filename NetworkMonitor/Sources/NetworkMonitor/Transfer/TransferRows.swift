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

    private let titleLabel: NSTextField
    private let stateLabel: NSTextField
    private let track = MenuPanelTrackView(fillColor: .systemBlue)
    private let checkIcon = NSImageView()
    private var currentState: TransferState

    init(session: TransferSession) {
        currentState = session.state
        titleLabel = MenuPanelLabel.text(Self.titleText(session), font: MenuPanelStyle.bodyFont)
        stateLabel = MenuPanelLabel.text(Self.stateText(session),
                                         font: MenuPanelStyle.sectionFont,
                                         color: Self.stateColor(session))
        super.init(height: 44, onClick: {})
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

        let vertical = NSStackView(views: [topRow, track])
        vertical.orientation = .vertical
        vertical.alignment = .leading
        vertical.spacing = 6
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
