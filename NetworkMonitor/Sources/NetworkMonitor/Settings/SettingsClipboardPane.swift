import AppKit
import NetworkMonitorCore

// MARK: - 剪贴板设置页

/// 剪贴板设置 — 面板唤起、采集范围、忽略列表与系统权限
///
/// 迁移自 `ClipboardSettingsWindow`：字段一一对应，布局改为原型的分组卡片。
/// 需要外部动作的项仍走 `ClipboardSettingsDelegate`（组合根实现）；
/// 开机自启动已移到「通用」页，这里不重复。
///
/// 文件拆分：忽略应用列表在 `SettingsClipboardPane+IgnoredApps.swift`，
/// 三页共用控件在 `SettingsSharedComponents.swift`。
final class SettingsClipboardPane: SettingsPaneView {

    /// 跨文件访问：忽略应用列表扩展使用
    let preferences: ClipboardPreferences

    /// 跨文件访问：忽略应用列表扩展需要通知采集器忽略集合变化
    weak var settingsDelegate: ClipboardSettingsDelegate?

    private let logger: LoggingService

    private let hotKeyRecorder = HotKeyRecorderView()
    private let positionPopup = NSPopUpButton()
    private let heightSlider = NSSlider()
    private let heightValueLabel = MenuPanelLabel.text("", font: SettingsStyle.rowValueFont,
                                                      color: .secondaryLabelColor)
    private let quickPasteSwitch = NSSwitch()
    private let captureModePopup = NSPopUpButton()
    private let maxItemsField = NSTextField()
    private let retentionField = NSTextField()

    // 忽略应用（跨文件访问：SettingsClipboardPane+IgnoredApps.swift）
    let ignoredToggleButton = NSButton()
    let ignoredInput = NSTextField()
    let ignoredCard = SettingsCardView()
    let ignoredListStack = NSStackView()
    var ignoredExpanded = false

    private let clipboardDot = SettingsStatusDotView()
    private let clipboardStateLabel = MenuPanelLabel.text("", font: .systemFont(ofSize: 12),
                                                         color: .secondaryLabelColor)
    private var clipboardSettingsButton = NSButton()
    private let accessibilityDot = SettingsStatusDotView()
    private let accessibilityStateLabel = MenuPanelLabel.text("", font: .systemFont(ofSize: 12),
                                                             color: .secondaryLabelColor)
    private var accessibilityButton = NSButton()

    init(preferences: ClipboardPreferences = ClipboardPreferences(),
         delegate: ClipboardSettingsDelegate? = nil,
         logger: LoggingService = AppContext.shared.logger) {
        self.preferences = preferences
        self.settingsDelegate = delegate
        self.logger = logger
        super.init(section: .clipboard)
    }

    // MARK: - 构建

    override func buildContent() {
        configureControls()

        let shortcutRow = SettingsRowView(title: "呼出面板快捷键")
        shortcutRow.trailingStack.addArrangedSubview(hotKeyRecorder)
        let positionRow = SettingsRowView(title: "面板位置")
        positionRow.trailingStack.addArrangedSubview(positionPopup)
        let heightRow = SettingsRowView(title: "面板高度")
        heightRow.trailingStack.addArrangedSubview(heightStack())
        let quickPasteRow = SettingsRowView(title: "⌘1–⌘9 快速粘贴")
        quickPasteRow.trailingStack.addArrangedSubview(quickPasteSwitch)

        let panelCard = SettingsCardView()
        [shortcutRow, positionRow, heightRow, quickPasteRow].forEach(panelCard.addRow)
        page.addCard(panelCard, sectionTitle: "唤起与面板")

        let captureModeRow = SettingsRowView(title: "采集模式")
        captureModeRow.trailingStack.addArrangedSubview(captureModePopup)
        let maxItemsRow = SettingsRowView(title: "最大条数")
        maxItemsRow.trailingStack.addArrangedSubview(maxItemsField)
        let retentionRow = SettingsRowView(title: "保留天数")
        retentionRow.trailingStack.addArrangedSubview(retentionField)
        let ignoredRow = SettingsRowView(title: "忽略的应用")
        ignoredRow.trailingStack.addArrangedSubview(ignoredToggleButton)

        let captureCard = SettingsCardView()
        [captureModeRow, maxItemsRow, retentionRow, ignoredRow].forEach(captureCard.addRow)
        page.addCard(captureCard, sectionTitle: "采集")

        buildIgnoredCard()
        page.addCard(ignoredCard)

        let clipboardRow = SettingsRowView(title: "剪贴板访问")
        clipboardRow.trailingStack.addArrangedSubview(clipboardDot)
        clipboardRow.trailingStack.addArrangedSubview(clipboardStateLabel)
        clipboardRow.trailingStack.addArrangedSubview(clipboardSettingsButton)
        let accessibilityRow = SettingsRowView(title: "辅助功能")
        accessibilityRow.trailingStack.addArrangedSubview(accessibilityDot)
        accessibilityRow.trailingStack.addArrangedSubview(accessibilityStateLabel)
        accessibilityRow.trailingStack.addArrangedSubview(accessibilityButton)

        let permissionCard = SettingsCardView()
        [clipboardRow, accessibilityRow].forEach(permissionCard.addRow)
        page.addCard(permissionCard, sectionTitle: "权限")

        page.addNote("辅助功能用于 Paste Stack 的 ⌘V 监听；剪贴板访问权限由系统在首次读取时询问。"
                     + "开机自启动已移至「通用」页。")
    }

    private func heightStack() -> NSView {
        let stack = NSStackView(views: [heightSlider, heightValueLabel])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        return stack
    }

    private func configureControls() {
        hotKeyRecorder.combo = preferences.panelToggleHotKey
        hotKeyRecorder.onChange = { [weak self] combo in self?.applyHotKey(combo) }
        hotKeyRecorder.setAccessibilityLabel("呼出面板快捷键")

        configurePopup(positionPopup,
                       items: [ClipboardPanelPosition.mouseScreen, .primaryScreen, .mouseLocation],
                       labels: { $0.label },
                       rawValues: { $0.rawValue },
                       action: #selector(positionChanged),
                       accessibility: "面板位置")

        heightSlider.minValue = 200
        heightSlider.maxValue = 480
        heightSlider.isContinuous = true
        heightSlider.target = self
        heightSlider.action = #selector(heightChanged)
        heightSlider.widthAnchor.constraint(equalToConstant: 130).isActive = true
        heightSlider.setAccessibilityLabel("面板高度")
        heightValueLabel.alignment = .right
        heightValueLabel.widthAnchor.constraint(equalToConstant: 46).isActive = true
        heightValueLabel.setContentHuggingPriority(.required, for: .horizontal)
        heightValueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        quickPasteSwitch.target = self
        quickPasteSwitch.action = #selector(quickPasteChanged)
        quickPasteSwitch.setAccessibilityLabel("⌘1–⌘9 快速粘贴")

        configurePopup(captureModePopup,
                       items: [ClipboardCaptureMode.polling, .onDemand],
                       labels: { $0.label },
                       rawValues: { $0.rawValue },
                       action: #selector(captureModeChanged),
                       accessibility: "采集模式")

        for (field, name) in [(maxItemsField, "最大条数"), (retentionField, "保留天数")] {
            field.controlSize = .small
            field.alignment = .right
            field.font = SettingsStyle.rowValueFont
            field.target = self
            field.action = #selector(limitsChanged)
            field.delegate = self
            field.widthAnchor.constraint(equalToConstant: 64).isActive = true
            field.setAccessibilityLabel(name)
        }

        ignoredInput.placeholderString = "com.example.app"
        ignoredInput.controlSize = .small
        ignoredInput.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
        ignoredInput.widthAnchor.constraint(equalToConstant: 176).isActive = true
        ignoredInput.setAccessibilityLabel("要忽略的应用 bundleID")
        ignoredToggleButton.target = self
        ignoredToggleButton.action = #selector(toggleIgnoredList)
        updateIgnoredToggleTitle(count: 0)

        for label in [clipboardStateLabel, accessibilityStateLabel] {
            label.alignment = .right
            label.widthAnchor.constraint(equalToConstant: 88).isActive = true
            label.setContentHuggingPriority(.required, for: .horizontal)
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        clipboardSettingsButton = SettingsLinkButton.make("前往系统设置",
                                                          target: self,
                                                          action: #selector(requestClipboardAccess))
        accessibilityButton = SettingsLinkButton.make("前往系统设置",
                                                      target: self,
                                                      action: #selector(requestAccessibility))
    }

    /// 下拉框统一配置：选项标题 + representedObject 存 rawValue
    private func configurePopup<Item>(_ popup: NSPopUpButton,
                                      items: [Item],
                                      labels: (Item) -> String,
                                      rawValues: (Item) -> String,
                                      action: Selector,
                                      accessibility: String) {
        popup.controlSize = .small
        for item in items {
            popup.addItem(withTitle: labels(item))
            popup.lastItem?.representedObject = rawValues(item)
        }
        popup.target = self
        popup.action = action
        popup.widthAnchor.constraint(equalToConstant: 148).isActive = true
        popup.setAccessibilityLabel(accessibility)
    }

    // MARK: - 刷新

    override func refresh() {
        hotKeyRecorder.combo = preferences.panelToggleHotKey
        hotKeyRecorder.isConflicted = false
        positionPopup.selectItem(at: index(of: preferences.panelPosition.rawValue, in: positionPopup))
        let height = min(max(preferences.panelHeight, heightSlider.minValue), heightSlider.maxValue)
        heightSlider.doubleValue = height
        heightValueLabel.stringValue = "\(Int(height)) pt"
        quickPasteSwitch.state = preferences.quickPasteEnabled ? .on : .off
        captureModePopup.selectItem(at: index(of: preferences.captureMode.rawValue, in: captureModePopup))
        maxItemsField.stringValue = "\(preferences.maxItems)"
        retentionField.stringValue = "\(preferences.retentionDays)"
        reloadIgnoredApps()
        refreshPermissionStatus()
    }

    private func index(of rawValue: String, in popup: NSPopUpButton) -> Int {
        popup.itemArray.firstIndex { ($0.representedObject as? String) == rawValue } ?? 0
    }

    /// 权限状态：无权限时必须显式呈现并提供跳转（不得静默失败）
    private func refreshPermissionStatus() {
        let granted = settingsDelegate?.settingsAccessibilityGranted() ?? false
        accessibilityDot.setColor(granted ? .systemGreen : .systemOrange)
        accessibilityStateLabel.stringValue = granted ? "已授权" : "待授权"
        accessibilityButton.isHidden = granted

        var accessText = "未知"
        var accessColor: NSColor = .tertiaryLabelColor
        var needsSettings = true
        if #available(macOS 15.4, *) {
            switch NSPasteboard.general.accessBehavior {
            case .alwaysAllow:
                accessText = "已允许"
                accessColor = .systemGreen
                needsSettings = false
            case .alwaysDeny:
                accessText = "已被拒绝"
                accessColor = .systemOrange
            case .ask:
                accessText = "每次询问"
                accessColor = .systemOrange
            default:
                accessText = "默认"
            }
        }
        clipboardDot.setColor(accessColor)
        clipboardStateLabel.stringValue = accessText
        clipboardSettingsButton.isHidden = !needsSettings
    }

    // MARK: - 动作

    /// 快捷键变更：注册失败不静默 —— 录制控件标红并保持原组合键
    private func applyHotKey(_ combo: HotKeyCombo) {
        let success = settingsDelegate?.settingsDidChangeHotKey(combo) ?? false
        hotKeyRecorder.isConflicted = !success
        if success { preferences.panelToggleHotKey = combo }
        logger.info("剪贴板唤起快捷键更新：\(combo.displayString)，注册成功=\(success)")
    }

    @objc private func quickPasteChanged() {
        preferences.quickPasteEnabled = quickPasteSwitch.state == .on
    }

    @objc private func positionChanged() {
        guard let raw = positionPopup.selectedItem?.representedObject as? String,
              let position = ClipboardPanelPosition(rawValue: raw) else { return }
        preferences.panelPosition = position
    }

    @objc private func heightChanged() {
        preferences.panelHeight = heightSlider.doubleValue
        heightValueLabel.stringValue = "\(Int(heightSlider.doubleValue)) pt"
    }

    @objc private func limitsChanged() {
        commitLimits()
    }

    private func commitLimits() {
        preferences.maxItems = Int(maxItemsField.stringValue) ?? ClipboardLimit.defaultMaxItems
        preferences.retentionDays = Int(retentionField.stringValue) ?? ClipboardLimit.defaultRetentionDays
        maxItemsField.stringValue = "\(preferences.maxItems)"
        retentionField.stringValue = "\(preferences.retentionDays)"
    }

    @objc private func captureModeChanged() {
        guard let raw = captureModePopup.selectedItem?.representedObject as? String,
              let mode = ClipboardCaptureMode(rawValue: raw) else { return }
        preferences.captureMode = mode
        settingsDelegate?.settingsDidChangeCaptureMode()
    }

    @objc private func requestAccessibility() {
        settingsDelegate?.settingsDidRequestAccessibilityPermission()
        refreshPermissionStatus()
    }

    @objc private func requestClipboardAccess() {
        settingsDelegate?.settingsDidRequestClipboardSettings()
    }
}

// MARK: - 文本字段提交

extension SettingsClipboardPane: NSTextFieldDelegate {

    /// 失焦也算提交，避免改完数字直接点别处导致设置丢失
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField,
              field === maxItemsField || field === retentionField else { return }
        commitLimits()
    }
}
