import AppKit
import NetworkMonitorCore

// MARK: - 未配置态

/// 未配置态 — 图标 + 标题 + 说明 + API Key 输入行 + 官方链接
///
/// 凭据只写偏好存储（`PreferencesBillingCredentialStore`），界面用 `NSSecureTextField` 掩码输入，
/// 保存后不保留明文，输入框立即清空。
final class BillingCredentialSetupView: NSView {

    /// 「保存并查询」提交 API Key
    var onSave: ((String) -> Void)?
    /// 「在 ollama.com 获取 API Key」
    var onOpenSite: (() -> Void)?

    private let secureField = NSSecureTextField()
    private let fieldBox = BillingFieldBoxView()
    private let saveRow = BillingPrimaryButtonRow(title: "保存并查询")
    private let linkRow = BillingLinkRow(text: "在 ollama.com 获取 API Key",
                                         symbolName: "arrow.up.right.square")
    private let noteLabel = BillingCredentialSetupView.makeNoteLabel()
    private let titleLabel = MenuPanelLabel.text("配置 API Key 后查看额度",
                                                 font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                                                 color: .labelColor)
    private let iconTile = BillingIconTileView(symbolName: "key")

    // MARK: - 初始化

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        secureField.isBordered = false
        secureField.drawsBackground = false
        secureField.focusRingType = .none
        secureField.font = BillingPaneStyle.monoFont
        secureField.textColor = .labelColor
        secureField.placeholderString = "API Key"
        secureField.translatesAutoresizingMaskIntoConstraints = false
        secureField.delegate = self
        secureField.target = self
        secureField.action = #selector(submitFromField)
        secureField.setAccessibilityLabel("API Key")

        fieldBox.translatesAutoresizingMaskIntoConstraints = false
        fieldBox.addSubview(secureField)
        NSLayoutConstraint.activate([
            fieldBox.heightAnchor.constraint(equalToConstant: 26),
            secureField.leadingAnchor.constraint(equalTo: fieldBox.leadingAnchor, constant: 8),
            secureField.trailingAnchor.constraint(equalTo: fieldBox.trailingAnchor, constant: -8),
            secureField.centerYAnchor.constraint(equalTo: fieldBox.centerYAnchor),
        ])

        saveRow.onClick = { [weak self] in self?.submit() }
        linkRow.onClick = { [weak self] in self?.onOpenSite?() }

        let fieldRow = NSStackView(views: [fieldBox, saveRow])
        fieldRow.orientation = .horizontal
        fieldRow.alignment = .centerY
        fieldRow.spacing = 6
        fieldBox.setContentHuggingPriority(.defaultLow, for: .horizontal)

        titleLabel.alignment = .center
        let stack = NSStackView(views: [iconTile, titleLabel, noteLabel, fieldRow, linkRow])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            fieldRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            noteLabel.widthAnchor.constraint(equalToConstant: 230),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 键盘可达行：保存按钮 → 官方链接
    var focusableRows: [MenuPanelRow] { [saveRow, linkRow] }

    /// 同步凭据输入框占位文案（provider.credentialHint）
    func update(placeholder: String) {
        secureField.placeholderString = placeholder
        secureField.setAccessibilityLabel(placeholder)
    }

    // MARK: - 提交

    @objc private func submitFromField() {
        submit()
    }

    /// 提交输入内容（空值忽略；提交后清空输入框，避免明文驻留）
    private func submit() {
        let key = secureField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        onSave?(key)
        secureField.stringValue = ""
    }

    /// 说明段落（10.5pt，行高 1.5，最大宽 230）
    private static func makeNoteLabel() -> NSTextField {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.5
        paragraph.alignment = .center
        let text = "余额与用量来自 Ollama 云端接口，Key 只保存在本机偏好设置中。"
        let label = NSTextField(labelWithAttributedString: NSAttributedString(
            string: text,
            attributes: [.font: BillingPaneStyle.noteFont,
                         .foregroundColor: BillingPaneStyle.secondaryText,
                         .paragraphStyle: paragraph]))
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.preferredMaxLayoutWidth = 230
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }
}

// MARK: - 输入框焦点边框

extension BillingCredentialSetupView: NSTextFieldDelegate {
    func controlTextDidBeginEditing(_ obj: Notification) {
        fieldBox.setFocused(true)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        fieldBox.setFocused(false)
    }
}

// MARK: - 输入框容器

/// 输入框底 — 26pt 高、圆角 6、系统文本底色 + 1pt 边框（聚焦时强调色）
final class BillingFieldBoxView: NSView {

    private var isFocused = false

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 焦点态（边框变强调色）
    func setFocused(_ focused: Bool) {
        guard isFocused != focused else { return }
        isFocused = focused
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: 6, yRadius: 6)
        NSColor.textBackgroundColor.setFill()
        path.fill()
        (isFocused ? MenuPanelStyle.accentColor : BillingPaneStyle.fieldBorder).setStroke()
        path.lineWidth = isFocused ? 1.5 : 1
        path.stroke()
    }
}

// MARK: - 图标容器

/// 34×34 圆角图标容器（强调色 12% 底）
final class BillingIconTileView: NSView {

    init(symbolName: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        if let icon = MenuPanelLabel.symbol(symbolName, pointSize: 17, color: MenuPanelStyle.accentColor) {
            addSubview(icon)
            NSLayoutConstraint.activate([
                icon.centerXAnchor.constraint(equalTo: centerXAnchor),
                icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        }
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 34),
            heightAnchor.constraint(equalToConstant: 34),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        BillingPaneStyle.accentTile.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 9, yRadius: 9).fill()
        super.draw(dirtyRect)
    }
}

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

// MARK: - 链接行

/// 强调色链接行 — 文字 + 可选外链图标，可点击、可键盘聚焦
final class BillingLinkRow: MenuPanelRow {

    init(text: String, symbolName: String? = nil,
         font: NSFont = BillingPaneStyle.noteFont) {
        let iconView = symbolName.flatMap {
            MenuPanelLabel.symbol($0, pointSize: 10, color: MenuPanelStyle.accentColor)
        }
        super.init(height: 20, onClick: nil)
        contentStack.spacing = 4
        contentStack.addArrangedSubview(MenuPanelLabel.text(text, font: font,
                                                            color: MenuPanelStyle.accentColor))
        if let iconView { contentStack.addArrangedSubview(iconView) }
        setAccessibilityLabel(text)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        let fitting = contentStack.fittingSize
        return NSSize(width: fitting.width + 8, height: 20)
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
