import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 剪贴板设置页（识别开关见 SettingsClipboardOCRRow.swift）

/// 剪贴板设置 — 面板唤起、采集范围、忽略列表与系统权限
///
/// 需要外部动作的项走 `ClipboardSettingsDelegate`（组合根实现）；
/// 文件拆分：忽略列表在 +IgnoredApps、存储卡在 +Storage、权限卡在 +Permission、
/// 识别开关在 `SettingsClipboardOCRRow.swift`。
final class SettingsClipboardPane: SettingsPaneView, SettingsNotificationEventHosting {

    /// 跨文件访问：忽略列表 / 存储 / 识别开关三处扩展共用
    let preferences: ClipboardPreferences
    weak var settingsDelegate: ClipboardSettingsDelegate?
    let logger: LoggingService

    /// 跨文件访问：权限扩展（SettingsClipboardPane+Permission.swift）按它渲染状态卡
    let permissions: any SystemPermissionProviding

    private let hotKeyRecorder = HotKeyRecorderView()
    private let positionPopup = NSPopUpButton()
    private let heightSlider = NSSlider()
    private let heightValueLabel = MenuPanelLabel.text("", font: SettingsTheme.rowValueFont,
                                                       color: SettingsTheme.textSecondary)
    private let quickPasteSwitch = NSSwitch()
    /// 剪贴板动作的通知行（放宽为 internal：DEBUG 快照要按协议取到它）
    let notificationCard: SettingsNotificationEventCard
    private let captureModePopup = NSPopUpButton()
    /// 暂停采集一行（开关 + 定时时长；装配与回显见 SettingsClipboardPauseSection）
    private lazy var pauseSection = ClipboardPauseSection(preferences: preferences, delegate: settingsDelegate)
    private lazy var ocrRow = SettingsClipboardOCRRow(preferences: preferences, logger: logger)
    private let maxItemsField = NSTextField()
    private let retentionField = NSTextField()

    // 忽略应用（跨文件访问：SettingsClipboardPane+IgnoredApps.swift）
    let ignoredToggleButton = NSButton()
    let ignoredInput = NSTextField()
    let ignoredCard = SettingsCardView()
    let ignoredListStack = NSStackView()
    var ignoredExpanded = false

    // 图片存储（跨文件访问：SettingsClipboardPane+Storage.swift 构建与动作）
    let usageLabel = MenuPanelLabel.text("", font: SettingsTheme.rowValueFont,
                                         color: SettingsTheme.textPrimary)
    let usageDetailLabel = MenuPanelLabel.text("", font: SettingsTheme.rowSubtitleFont,
                                               color: SettingsTheme.textSecondary)
    var openDirectoryButton = NSButton()
    var clearStorageButton = NSButton()
    var storageActionRow: SettingsRowView?

    // 系统权限卡（三类权限 × 三态；构建与刷新在 SettingsPermissionCard.swift）
    /// 放宽为 internal：页头胶囊扩展（SettingsClipboardPane+Permission）刷新时要用
    var permissionCard: SystemPermissionCard?
    /// 最近一次图片存储读数（页头胶囊同时表达「权限合计 + 文件数」，两处共用这一份）
    var lastStorageUsage: ClipboardStorageUsage.Summary?

    init(preferences: ClipboardPreferences = ClipboardPreferences(),
         delegate: ClipboardSettingsDelegate? = nil,
         permissions: any SystemPermissionProviding,
         notificationContext: SettingsNotificationEventContext,
         logger: LoggingService = AppContext.shared.logger) {
        self.preferences = preferences
        self.settingsDelegate = delegate
        self.permissions = permissions
        self.notificationCard = SettingsNotificationEventCard(events: [.clipboardAction],
                                                              context: notificationContext)
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

        let pauseRow = SettingsRowView(title: "暂停采集（复制的内容不入库）")
        pauseSection.attach(to: pauseRow)
        let captureModeRow = SettingsRowView(title: "采集模式")
        captureModeRow.trailingStack.addArrangedSubview(captureModePopup)
        let imageOCRRow = ocrRow.row
        let maxItemsRow = SettingsRowView(title: "最大条数")
        maxItemsRow.trailingStack.addArrangedSubview(maxItemsField)
        let retentionRow = SettingsRowView(title: "保留天数")
        retentionRow.trailingStack.addArrangedSubview(retentionField)
        let ignoredRow = SettingsRowView(title: "忽略的应用")
        ignoredRow.trailingStack.addArrangedSubview(ignoredToggleButton)

        let captureCard = SettingsCardView()
        [pauseRow, captureModeRow, imageOCRRow, maxItemsRow, retentionRow, ignoredRow].forEach(captureCard.addRow)
        page.addCard(captureCard, sectionTitle: "采集")

        buildIgnoredCard()
        page.addCard(ignoredCard)

        page.addCard(notificationCard.card, sectionTitle: "通知与音效")
        buildStorageCard()
        buildPermissionCard()

        page.addNote("开机自启动已移至「通用」页。")
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

        heightSlider.minValue = ClipboardPreferences.heightRange.lowerBound
        heightSlider.maxValue = ClipboardPreferences.heightRange.upperBound
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
            field.font = SettingsTheme.rowValueFont
            field.target = self
            field.action = #selector(limitsChanged)
            field.delegate = self
            field.widthAnchor.constraint(equalToConstant: 64).isActive = true
            field.setAccessibilityLabel(name)
            SettingsControlChrome.applyStandardHeight(to: field)
        }

        ignoredInput.placeholderString = "com.example.app"
        ignoredInput.controlSize = .small
        ignoredInput.font = SettingsTheme.rowValueFont
        ignoredInput.widthAnchor.constraint(equalToConstant: 176).isActive = true
        SettingsControlChrome.applyStandardHeight(to: ignoredInput)
        ignoredInput.setAccessibilityLabel("要忽略的应用 bundleID")
        ignoredToggleButton.target = self
        ignoredToggleButton.action = #selector(toggleIgnoredList)
        updateIgnoredToggleTitle(count: 0)

    }

    /// 系统权限卡：三类权限各一行 + 卡头「检测状态」+ 卡下说明（全部在 SystemPermissionCard 里）
    private func buildPermissionCard() {
        let card = SystemPermissionCard(permissions: permissions, logger: logger)
        permissionCard = card
        card.attach(to: page)
    }

    /// 下拉框统一配置：选项标题 + representedObject 存 rawValue
    private func configurePopup<Item>(_ popup: NSPopUpButton,
                                      items: [Item],
                                      labels: (Item) -> String,
                                      rawValues: (Item) -> String,
                                      action: Selector,
                                      accessibility: String) {
        popup.controlSize = .small
        popup.font = SettingsTheme.rowTitleFont
        for item in items {
            popup.addItem(withTitle: labels(item))
            popup.lastItem?.representedObject = rawValues(item)
        }
        popup.target = self
        popup.action = action
        popup.widthAnchor.constraint(equalToConstant: 148).isActive = true
        popup.setAccessibilityLabel(accessibility)
        SettingsControlChrome.applyStandardHeight(to: popup)
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
        pauseSection.refresh()
        ocrRow.refresh()
        captureModePopup.selectItem(at: index(of: preferences.captureMode.rawValue, in: captureModePopup))
        maxItemsField.stringValue = "\(preferences.maxItems)"
        retentionField.stringValue = "\(preferences.retentionDays)"
        reloadIgnoredApps()
        notificationCard.refresh()
        // 权限在切页时重读一次（另两处是应用激活与卡头「检测状态」），保证看到的永远是最新快照
        refreshPermissionChip()
        // 目录只扫一次：存储卡与页头胶囊共用同一份读数（图片目录可能上千个文件，
        // 两处各扫一遍等于把打开设置页的磁盘开销翻倍）
        let imageUsage = settingsDelegate?.settingsClipboardImageUsage() ?? ClipboardStorageUsage.empty
        refreshStorageCard(usage: imageUsage)
    }

    private func index(of rawValue: String, in popup: NSPopUpButton) -> Int {
        popup.itemArray.firstIndex { ($0.representedObject as? String) == rawValue } ?? 0
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
