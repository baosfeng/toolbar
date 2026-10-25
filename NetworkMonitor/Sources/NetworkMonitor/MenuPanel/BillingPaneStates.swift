import AppKit
import NetworkMonitorCore

// MARK: - 面板按钮与错误条

// 凭据输入已统一收进设置窗口（额度 Provider 页），本文件只保留额度页仍使用的
// 主按钮行、错误条与「重试」行；原「未配置态」凭据表单及其输入框 / 图标块 / 链接行已移除。

// MARK: - 主按钮行

/// 主按钮行 — 强调色底 + 白字，可点击、可键盘聚焦
final class BillingPrimaryButtonRow: MenuPanelRow {

    private let titleLabel: NSTextField
    private let buttonWidth: CGFloat

    init(title: String) {
        let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        titleLabel = MenuPanelLabel.text(title, font: font, color: .white)
        buttonWidth = ceil((title as NSString).size(withAttributes: [.font: font]).width) + 20
        super.init(height: 26, onClick: nil)
        contentStack.addArrangedSubview(titleLabel)
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        widthAnchor.constraint(equalToConstant: buttonWidth).isActive = true
        setAccessibilityLabel(title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        NSSize(width: buttonWidth, height: 26)
    }

    override func draw(_ dirtyRect: NSRect) {
        MenuPanelStyle.accentColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        super.draw(dirtyRect)
        // 强调色底上看不出强调色焦点环，键盘聚焦时补一圈白环
        if isKeyboardFocused {
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: -2, dy: -2),
                                    xRadius: 8, yRadius: 8)
            ring.lineWidth = 2
            NSColor.white.withAlphaComponent(0.9).setStroke()
            ring.stroke()
        }
    }
}

// MARK: - 错误条

/// 错误条 — 危险色 10% 底 + 警告图标 + 文案 + 下划线「重试」
///
/// 显示在页头与余额卡之间；余额/用量保留上次成功数据（由状态管理器保证）。
final class BillingErrorBannerView: NSView {

    /// 点「重试」
    var onRetry: (() -> Void)?

    private let messageLabel = BillingErrorBannerView.makeMessageLabel()
    private let retryRow = BillingRetryRow()

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        retryRow.onClick = { [weak self] in self?.onRetry?() }

        let iconView = MenuPanelLabel.symbol("exclamationmark.triangle.fill", pointSize: 13,
                                             color: .systemRed)
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .top
        stack.spacing = 7
        if let iconView { stack.addArrangedSubview(iconView) }
        stack.addArrangedSubview(messageLabel)
        stack.addArrangedSubview(MenuPanelLabel.spacer())
        stack.addArrangedSubview(retryRow)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
        setAccessibilityRole(.group)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 键盘可达行：重试
    var retryButtonRow: MenuPanelRow { retryRow }

    /// 更新错误文案（来自 `BillingError.userMessage`）
    func update(message: String) {
        messageLabel.stringValue = message
        messageLabel.toolTip = message
    }

    override func draw(_ dirtyRect: NSRect) {
        BillingPaneStyle.dangerSoft.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        super.draw(dirtyRect)
    }

    private static func makeMessageLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = BillingPaneStyle.noteFont
        label.textColor = .systemRed
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byWordWrapping
        label.preferredMaxLayoutWidth = 170
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }
}

// MARK: - 重试按钮行

/// 下划线「重试」— 危险色文字，可点击、可键盘聚焦
final class BillingRetryRow: MenuPanelRow {

    init() {
        super.init(height: 18, onClick: nil)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10.5, weight: .semibold),
            .foregroundColor: NSColor.systemRed,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        let label = NSTextField(labelWithAttributedString: NSAttributedString(string: "重试",
                                                                             attributes: attributes))
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        contentStack.addArrangedSubview(label)
        setAccessibilityLabel("重试")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        let fitting = contentStack.fittingSize
        return NSSize(width: fitting.width + 8, height: 18)
    }
}
