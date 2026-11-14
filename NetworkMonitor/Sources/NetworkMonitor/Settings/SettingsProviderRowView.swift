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
    /// 重命名实例（仅命名实例提供入口）
    var onRename: (() -> Void)?
    /// 删除实例（仅命名实例提供入口；二次确认由外部弹窗负责）
    var onDeleteInstance: (() -> Void)?
    /// 编辑区或清除确认展开 / 收起（外部据此锁定其他行）
    var onEditingChanged: ((Bool) -> Void)?

    // MARK: - 子视图

    let provider: any BillingProvider
    /// 实例信息（id 即实例标识；默认实例的 id 等于 kindID）
    let instance: BillingInstance
    let tile: ProviderIconTileView
    let nameLabel = MenuPanelLabel.text("", font: SettingsTheme.rowTitleFont,
                                       color: SettingsTheme.textPrimary)
    let dotView = ProviderStatusDotView()
    let statusLabel = MenuPanelLabel.text("", font: SettingsTheme.rowSubtitleFont,
                                          color: SettingsTheme.textSecondary)
    // 错误文案是「这一条不能用」，属于破坏性语义：走 destructive 单一出口，不直接写 systemRed
    let errorLabel = MenuPanelLabel.text("", font: SettingsTheme.noteFont,
                                         color: SettingsTheme.destructive)
    let toggle = NSSwitch()
    let editButton: NSButton
    let clearButton: NSButton
    let configButton: NSButton
    /// 「重命名」（仅命名实例可见）
    let renameButton: NSButton
    /// 「删除实例」（仅命名实例可见，红色）
    let deleteButton: NSButton

    let editorView = NSView()
    let field = NSSecureTextField()
    let saveButton: NSButton
    let cancelButton: NSButton
    let editorMessage = MenuPanelLabel.text("", font: SettingsTheme.noteFont,
                                            color: SettingsTheme.destructive)
    let editorNote = NSTextField(labelWithAttributedString: NSAttributedString(string: ""))

    let confirmView = NSView()
    let confirmButton: NSButton
    let confirmCancelButton: NSButton

    // MARK: - 展示状态

    var isEnabled = true
    var isConfigured = false
    var credentialMask: String?
    /// 生效凭据来源（存储 / 环境变量 / 未配置）— 状态行据此提示用户「另一个来源也有值」
    var credentialSource: BillingCredentialSource = .none
    var interval: TimeInterval = BillingRefreshScheduler.minimumInterval
    var lastAttempt: Date?
    var lastUpdated: Date?
    var isLoading = false
    var errorMessage: String?
    var isEditorExpanded = false
    var isConfirmExpanded = false

    // MARK: - 初始化

    init(provider: any BillingProvider, instance: BillingInstance) {
        self.provider = provider
        self.instance = instance
        tile = ProviderIconTileView(symbolName: provider.symbolName)
        editButton = Self.textButton("替换")
        clearButton = Self.textButton("清除")
        configButton = Self.textButton("配置凭据…")
        renameButton = Self.textButton("重命名")
        deleteButton = Self.textButton("删除", color: SettingsTheme.destructive)
        saveButton = Self.primaryButton("保存并查询")
        cancelButton = Self.textButton("取消")
        confirmButton = Self.textButton("确认清除", color: SettingsTheme.destructive)
        confirmCancelButton = Self.textButton("取消")
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        buildLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    // MARK: - 布局

    func buildLayout() {
        nameLabel.stringValue = instance.title
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
        renameButton.target = self
        renameButton.action = #selector(renameTapped)
        deleteButton.target = self
        deleteButton.action = #selector(deleteInstanceTapped)
        toggle.target = self
        toggle.action = #selector(toggleChanged)
        for (button, title) in [(editButton, "替换"), (clearButton, "清除"),
                               (configButton, "配置凭据"), (renameButton, "重命名"),
                               (deleteButton, "删除实例")] {
            button.setAccessibilityLabel("\(instance.title) \(title)")
        }
        toggle.setAccessibilityLabel("\(instance.title) 启用开关")

        let controls = NSStackView(views: [renameButton, deleteButton,
                                           editButton, clearButton, configButton, toggle])
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
        setAccessibilityLabel("\(instance.title) 额度 Provider")
        applyInstanceControls()
    }

    /// 默认实例不提供「重命名 / 删除」入口：删掉它等于让旧配置失去落点
    func applyInstanceControls() {
        let isNamed = instance.slug != nil
        renameButton.isHidden = !isNamed
        deleteButton.isHidden = !isNamed
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
                credentialSource: BillingCredentialSource = .none,
                interval: TimeInterval,
                state: BillingMonitor.ProviderState?,
                lastAttempt: Date?,
                now: Date) {
        self.isEnabled = isEnabled
        self.isConfigured = isConfigured
        self.credentialMask = credentialMask
        self.credentialSource = credentialSource
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
        // 已配置时状态行带上来源：环境变量回退是「只读的一条」，用户据此知道改的是哪一份
        let sourceNote = credentialSource == .environment ? "（环境变量）" : ""
        if !isEnabled {
            dotView.kind = .idle
            statusLabel.stringValue = isConfigured ? "已配置 · 已停用" : "未配置 · 已停用"
        } else if !isConfigured {
            dotView.kind = .warn
            statusLabel.stringValue = "未配置 · 尚未填写 Key"
        } else if let errorMessage, !errorMessage.isEmpty {
            dotView.kind = .warn
            statusLabel.stringValue = "已配置\(sourceNote) · \(refreshText())"
        } else {
            dotView.kind = .ok
            statusLabel.stringValue = "已配置\(sourceNote) · \(refreshText())"
        }
        nameLabel.textColor = isEnabled ? SettingsTheme.textPrimary : SettingsTheme.textSecondary
        tile.alphaValue = isEnabled ? 1 : 0.7

        errorLabel.stringValue = errorMessage ?? ""
        errorLabel.isHidden = !isEnabled || !isConfigured || errorMessage == nil
    }

    func applyControls() {
        toggle.state = isEnabled ? .on : .off
        // 同一 provider 只允许一份配置：已配置时只给「替换 / 清除」，未配置才给「配置凭据…」。
        // 环境变量回退不可从界面清除（那是 shell 里的东西），只给「替换」把存储中的凭据补上。
        let showsCredentialActions = isConfigured
        editButton.isHidden = !showsCredentialActions
        clearButton.isHidden = !showsCredentialActions || credentialSource == .environment
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

    @objc func renameTapped() {
        onRename?()
    }

    @objc func deleteInstanceTapped() {
        onDeleteInstance?()
    }

    /// 编辑其他行时锁定本行交互（视觉降透明，按钮与开关禁用）
    func setInteractionEnabled(_ enabled: Bool) {
        toggle.isEnabled = enabled
        editButton.isEnabled = enabled
        clearButton.isEnabled = enabled
        configButton.isEnabled = enabled
        renameButton.isEnabled = enabled
        deleteButton.isEnabled = enabled
        alphaValue = enabled ? 1 : 0.55
    }
}