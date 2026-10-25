import AppKit
import NetworkMonitorCore

// MARK: - provider 行

/// provider 行 — 图标 + 名称 + 状态点/状态文案 + 错误文案 + 行内凭据编辑
///
/// 行高与普通设置行一致（40pt 起），多行内容（状态、错误、展开区）自然撑高；
/// 展开区贴满卡片宽度（背景色块需要全宽），行内容左右内边距沿用 12pt。
final class ProviderRowView: NSView {

    // MARK: - 回调

    var onToggle: ((Bool) -> Void)?
    var onSave: ((String) -> Void)?
    var onClearConfirmed: (() -> Void)?
    /// 编辑区或清除确认展开 / 收起（外部据此锁定其他行）
    var onEditingChanged: ((Bool) -> Void)?

    // MARK: - 子视图

    let provider: any BillingProvider
    let tile: ProviderIconTileView
    let nameLabel = MenuPanelLabel.text("", font: SettingsStyle.rowTitleFont, color: .labelColor)
    let dotView = ProviderStatusDotView()
    let statusLabel = MenuPanelLabel.text("", font: SettingsStyle.rowSubtitleFont,
                                                  color: .secondaryLabelColor)
    let errorLabel = MenuPanelLabel.text("", font: SettingsStyle.noteFont,
                                                 color: .systemRed)
    let toggle = NSSwitch()
    let editButton: NSButton
    let clearButton: NSButton
    let configButton: NSButton

    let editorView = NSView()
    let field = NSSecureTextField()
    let saveButton: NSButton
    let cancelButton: NSButton
    let editorMessage = MenuPanelLabel.text("", font: SettingsStyle.noteFont,
                                                    color: .systemRed)
    let editorNote = NSTextField(labelWithAttributedString: NSAttributedString(string: ""))

    let confirmView = NSView()
    let confirmButton: NSButton
    let confirmCancelButton: NSButton

    // MARK: - 展示状态

    var isEnabled = true
    var isConfigured = false
    var credentialMask: String?
    var interval: TimeInterval = BillingRefreshScheduler.minimumInterval
    var lastAttempt: Date?
    var lastUpdated: Date?
    var isLoading = false
    var errorMessage: String?
    var isEditorExpanded = false
    var isConfirmExpanded = false

    // MARK: - 初始化

    init(provider: any BillingProvider) {
        self.provider = provider
        tile = ProviderIconTileView(symbolName: provider.symbolName)
        editButton = Self.textButton("替换")
        clearButton = Self.textButton("清除")
        configButton = Self.textButton("配置凭据…")
        saveButton = Self.primaryButton("保存并查询")
        cancelButton = Self.textButton("取消")
        confirmButton = Self.textButton("确认清除", color: .systemRed)
        confirmCancelButton = Self.textButton("取消")
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        buildLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    // MARK: - 布局

    func buildLayout() {
        nameLabel.stringValue = provider.displayName
        nameLabel.lineBreakMode = .byTruncatingTail
        statusLabel.lineBreakMode = .byTruncatingTail
        errorLabel.maximumNumberOfLines = 2
        errorLabel.lineBreakMode = .byWordWrapping
        errorLabel.isHidden = true
        dotView.translatesAutoresizingMaskIntoConstraints = false

        let meta = NSStackView(views: [dotView, statusLabel])
        meta.orientation = .horizontal
        meta.alignment = .centerY
        meta.spacing = 6

        let body = NSStackView(views: [nameLabel, meta, errorLabel])
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 3

        editButton.target = self
        editButton.action = #selector(editTapped)
        clearButton.target = self
        clearButton.action = #selector(clearTapped)
        configButton.target = self
        configButton.action = #selector(editTapped)
        toggle.target = self
        toggle.action = #selector(toggleChanged)
        for (button, title) in [(editButton, "替换"), (clearButton, "清除"), (configButton, "配置凭据")] {
            button.setAccessibilityLabel("\(provider.displayName) \(title)")
        }
        toggle.setAccessibilityLabel("\(provider.displayName) 启用开关")

        let controls = NSStackView(views: [editButton, clearButton, configButton, toggle])
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 10
        controls.setContentHuggingPriority(.required, for: .horizontal)

        let header = NSStackView(views: [tile, body, MenuPanelLabel.spacer(), controls])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 12
        header.edgeInsets = NSEdgeInsets(top: 10, left: SettingsStyle.rowInset,
                                         bottom: 10, right: SettingsStyle.rowInset)
        header.heightAnchor.constraint(greaterThanOrEqualToConstant: 58).isActive = true

        buildEditor()
        buildConfirm()

        let root = NSStackView(views: [header, editorView, confirmView])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 0
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor),
            root.trailingAnchor.constraint(equalTo: trailingAnchor),
            root.topAnchor.constraint(equalTo: topAnchor),
            root.bottomAnchor.constraint(equalTo: bottomAnchor),
            header.widthAnchor.constraint(equalTo: root.widthAnchor),
            editorView.widthAnchor.constraint(equalTo: root.widthAnchor),
            confirmView.widthAnchor.constraint(equalTo: root.widthAnchor),
        ])
        setAccessibilityLabel("\(provider.displayName) 额度 Provider")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateChromeColors()
    }

    // MARK: - 更新

    /// 刷新行状态（每次切页 / 每秒倒计时 tick 调用；不触碰编辑区输入内容）
    func update(isEnabled: Bool,
                isConfigured: Bool,
                credentialMask: String?,
                interval: TimeInterval,
                state: BillingMonitor.ProviderState?,
                lastAttempt: Date?,
                now: Date) {
        self.isEnabled = isEnabled
        self.isConfigured = isConfigured
        self.credentialMask = credentialMask
        self.interval = interval
        self.lastAttempt = lastAttempt
        lastUpdated = state?.lastUpdated
        isLoading = state?.isLoading ?? false
        errorMessage = state?.errorMessage

        applyStatus()
        applyControls()
        // 收起时不重建富文本，避免每秒无谓触发布局
        if isEditorExpanded {
            field.placeholderString = placeholderText()
            updateEditorNote(now: now)
        }
    }

    func applyStatus() {
        if !isEnabled {
            dotView.kind = .idle
            statusLabel.stringValue = isConfigured ? "已配置 · 已停用" : "未配置 · 已停用"
        } else if !isConfigured {
            dotView.kind = .warn
            statusLabel.stringValue = "未配置 · 尚未填写 Key"
        } else if let errorMessage, !errorMessage.isEmpty {
            dotView.kind = .warn
            statusLabel.stringValue = "已配置 · \(refreshText())"
        } else {
            dotView.kind = .ok
            statusLabel.stringValue = "已配置 · \(refreshText())"
        }
        nameLabel.textColor = isEnabled ? .labelColor : .secondaryLabelColor
        tile.alphaValue = isEnabled ? 1 : 0.7

        errorLabel.stringValue = errorMessage ?? ""
        errorLabel.isHidden = !isEnabled || !isConfigured || errorMessage == nil
    }

    func applyControls() {
        toggle.state = isEnabled ? .on : .off
        let showsCredentialActions = isConfigured
        editButton.isHidden = !showsCredentialActions
        clearButton.isHidden = !showsCredentialActions
        configButton.isHidden = showsCredentialActions
    }

    func refreshText() -> String {
        if isLoading { return "查询中" }
        guard let lastUpdated else { return "尚未刷新" }
        let seconds = Int(Date().timeIntervalSince(lastUpdated))
        if seconds < 60 { return "刚刚刷新" }
        if seconds < 3_600 { return "\(seconds / 60) 分钟前刷新" }
        if seconds < 86_400 { return "\(seconds / 3_600) 小时前刷新" }
        return "\(seconds / 86_400) 天前刷新"
    }

    func placeholderText() -> String {
        guard let mask = credentialMask else { return provider.credentialHint }
        return "已保存 \(mask)，输入新 Key 替换"
    }

    // MARK: - 开关

    @objc func toggleChanged() {
        onToggle?(toggle.state == .on)
    }

    /// 编辑其他行时锁定本行交互（视觉降透明，按钮与开关禁用）
    func setInteractionEnabled(_ enabled: Bool) {
        toggle.isEnabled = enabled
        editButton.isEnabled = enabled
        clearButton.isEnabled = enabled
        configButton.isEnabled = enabled
        alphaValue = enabled ? 1 : 0.55
    }
}