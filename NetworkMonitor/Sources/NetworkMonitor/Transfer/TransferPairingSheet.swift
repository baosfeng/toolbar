import AppKit
import NetworkMonitorCore

// MARK: - 配对弹窗

/// 配对弹窗 — 接收方展示 4 位 PIN，发送方输入 PIN
///
/// 用独立 NSPanel（跟随菜单栏 popover 收起后仍可见）：面板层级 `.floating`，
/// 接收方带「接受 / 拒绝」，发送方带输入框，两者都显示倒计时。
@MainActor
final class TransferPairingSheet {

    private var panel: NSPanel?
    private var countdownTimer: Timer?
    private var expiresAt: Date = .distantPast
    private let countdownLabel = NSTextField(labelWithString: "")
    private var onExpire: (() -> Void)?

    /// 是否正在显示
    var isVisible: Bool { panel?.isVisible ?? false }

    // MARK: - 接收方：展示 PIN

    func showReceive(pin: String, peerName: String, fileNames: [String], expiresAt: Date,
                     onApprove: @escaping () -> Void, onDeny: @escaping () -> Void,
                     onExpire: (() -> Void)? = nil) {
        close()
        self.expiresAt = expiresAt
        self.onExpire = onExpire

        let title = Self.titleLabel("\(peerName) 想发送 \(fileNames.count) 个文件")
        let subtitle = Self.hintLabel("把下面的配对码告诉对方，或直接接受")

        // 配对码：大字号 + 圆角底块，扫一眼即可读出
        let pinField = NSTextField(labelWithString: pin)
        pinField.font = NSFont.monospacedDigitSystemFont(ofSize: 46, weight: .semibold)
        pinField.alignment = .center
        pinField.isBezeled = false
        pinField.drawsBackground = false
        pinField.setAccessibilityLabel("配对码 \(pin)")
        let pinBox = NSView()
        pinBox.wantsLayer = true
        pinBox.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.22).cgColor
        pinBox.layer?.cornerRadius = 12
        pinField.translatesAutoresizingMaskIntoConstraints = false
        pinBox.addSubview(pinField)
        NSLayoutConstraint.activate([
            pinBox.widthAnchor.constraint(equalToConstant: 252),
            pinBox.heightAnchor.constraint(equalToConstant: 86),
            pinField.centerXAnchor.constraint(equalTo: pinBox.centerXAnchor),
            pinField.centerYAnchor.constraint(equalTo: pinBox.centerYAnchor),
        ])

        let filesLabel = Self.filesLabel(fileNames)

        let approve = Self.actionButton("接受", keyEquivalent: "\r") { onApprove() }
        let deny = Self.actionButton("拒绝", keyEquivalent: "\u{1b}") { onDeny() }
        let buttons = Self.horizontalStack([deny, approve])
        buttons.distribution = .fillEqually
        buttons.widthAnchor.constraint(equalToConstant: 252).isActive = true

        let content = Self.verticalStack([title, subtitle, pinBox, filesLabel, countdownLabel, buttons])
        present(content: content, title: "接收文件", size: NSSize(width: 348, height: 330))
    }

    // MARK: - 发送方：输入 PIN

    func showInput(peerName: String, onSubmit: @escaping (String) -> Void,
                   onCancel: @escaping () -> Void) {
        close()
        self.onExpire = nil
        self.expiresAt = .distantPast

        let title = Self.titleLabel("输入 \(peerName) 显示的 4 位配对码")
        let field = NSTextField()
        field.font = NSFont.monospacedDigitSystemFont(ofSize: 24, weight: .medium)
        field.alignment = .center
        field.placeholderString = "0000"
        field.maximumNumberOfLines = 1
        field.widthAnchor.constraint(equalToConstant: 160).isActive = true
        field.setAccessibilityLabel("配对码输入框")

        let confirm = Self.actionButton("配对", keyEquivalent: "\r") {
            let pin = field.stringValue.trimmingCharacters(in: .whitespaces)
            onSubmit(pin)
        }
        let cancel = Self.actionButton("取消", keyEquivalent: "\u{1b}") { onCancel() }
        let buttons = Self.horizontalStack([cancel, confirm])
        buttons.distribution = .fillEqually

        let content = Self.verticalStack([title, field, countdownLabel, buttons])
        present(content: content, title: "PIN 配对", size: NSSize(width: 260, height: 180))
        panel?.makeFirstResponder(field)
    }

    // MARK: - 关闭

    func close() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        onExpire = nil
        guard let current = panel else { return }
        panel = nil
        guard current.isVisible, TransferMotion.isEnabled, let content = current.contentView else {
            current.orderOut(nil)
            return
        }
        // 关闭：150ms 淡出（设计文档 §7.2）
        TransferMotion.fadeOut(content) { current.orderOut(nil) }
    }

    // MARK: - 内部

    private func present(content: NSStackView, title: String, size: NSSize) {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.titled, .closable],
                            backing: .buffered, defer: false)
        panel.title = title
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.contentView = content
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
        if let content = panel.contentView {
            TransferMotion.popIn(content)
        }
        startCountdown()
    }

    private func startCountdown() {
        countdownTimer?.invalidate()
        guard expiresAt > Date() else {
            countdownLabel.stringValue = ""
            return
        }
        updateCountdown()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tickCountdown() }
        }
    }

    private func tickCountdown() {
        guard expiresAt > Date() else {
            countdownTimer?.invalidate()
            countdownTimer = nil
            countdownLabel.stringValue = "已超时"
            onExpire?()
            return
        }
        updateCountdown()
    }

    private func updateCountdown() {
        let seconds = max(0, Int(expiresAt.timeIntervalSinceNow.rounded()))
        if expiresAt > Date() {
            countdownLabel.stringValue = "\(seconds) 秒后自动拒绝"
            countdownLabel.textColor = seconds <= 10 ? .systemRed : .systemOrange
        } else {
            countdownLabel.stringValue = ""
        }
    }

    // MARK: - 控件工厂

    private static func titleLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 15.5, weight: .semibold)
        label.alignment = .center
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byWordWrapping
        return label
    }

    private static func hintLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 12.5)
        label.textColor = NSColor.labelColor.withAlphaComponent(0.72)
        label.alignment = .center
        label.maximumNumberOfLines = 3
        label.lineBreakMode = .byTruncatingMiddle
        return label
    }

    /// 文件清单：最多 3 行 + 「等 N 个文件」，字号跟提示一致
    private static func filesLabel(_ names: [String]) -> NSTextField {
        let shown = Array(names.prefix(3))
        var lines = shown.map { "· \($0)" }
        if names.count > shown.count { lines.append("等 \(names.count) 个文件") }
        let label = NSTextField(labelWithString: lines.joined(separator: "\n"))
        label.font = NSFont.systemFont(ofSize: 13)
        label.textColor = NSColor.labelColor.withAlphaComponent(0.72)
        label.alignment = .left
        label.maximumNumberOfLines = 4
        label.lineBreakMode = .byTruncatingMiddle
        label.widthAnchor.constraint(equalToConstant: 252).isActive = true
        return label
    }

    private static func actionButton(_ title: String, keyEquivalent: String,
                                     action: @escaping () -> Void) -> NSButton {
        let button = ClosureButton(title: title, action: action)
        button.keyEquivalent = keyEquivalent
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        button.heightAnchor.constraint(equalToConstant: 32).isActive = true
        return button
    }

    private static func horizontalStack(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = 8
        return stack
    }

    private static func verticalStack(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        return stack
    }
}

// MARK: - 闭包按钮

/// 以闭包为动作的按钮（避免每处写 @objc 选择子）
final class ClosureButton: NSButton {
    private let handler: () -> Void

    init(title: String, action: @escaping () -> Void) {
        handler = action
        super.init(frame: .zero)
        self.title = title
        target = self
        self.action = #selector(performAction)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    @objc private func performAction() {
        handler()
    }
}
