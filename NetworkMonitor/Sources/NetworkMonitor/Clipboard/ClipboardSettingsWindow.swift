import AppKit
import NetworkMonitorCore
import ServiceManagement

// MARK: - 设置窗回调

/// 设置窗回调 — 由组合根实现（设置窗不直接持有服务）
@MainActor
protocol ClipboardSettingsDelegate: AnyObject {
    /// 唤起快捷键变化；返回 false 表示注册冲突（设置窗标记冲突态）
    func settingsDidChangeHotKey(_ combo: HotKeyCombo) -> Bool
    /// 采集模式变化（需按新模式重启采集器）
    func settingsDidChangeCaptureMode()
    /// 忽略应用列表变化
    func settingsDidChangeIgnoredApps()
    /// 当前是否已获得辅助功能权限
    func settingsAccessibilityGranted() -> Bool
    /// 请求辅助功能权限（跳转系统设置）
    func settingsDidRequestAccessibilityPermission()
    /// 跳转系统设置隐私面板（剪贴板访问权限）
    func settingsDidRequestClipboardSettings()
}

// MARK: - 设置窗

/// 剪贴板设置窗 — 快捷键、快速粘贴、采集模式、面板位置与高度、上限、黑名单、权限状态、开机自启
@MainActor
final class ClipboardSettingsWindow: NSObject, NSWindowDelegate {

    private let window: NSWindow
    private let preferences: ClipboardPreferences
    private let logger: LoggingService
    private weak var settingsDelegate: ClipboardSettingsDelegate?

    private let hotKeyRecorder = HotKeyRecorderView()
    private let quickPasteCheckbox = NSButton(checkboxWithTitle: "启用 ⌘1–⌘9 快速粘贴", target: nil, action: nil)
    private let positionPopup = NSPopUpButton()
    private let heightSlider = NSSlider()
    private let heightLabel = NSTextField(labelWithString: "")
    private let maxItemsField = NSTextField()
    private let retentionField = NSTextField()
    private let captureModePopup = NSPopUpButton()
    private let ignoredStack = NSStackView()
    private let ignoredInput = NSTextField()
    private let accessibilityLabel = NSTextField(labelWithString: "")
    private let accessibilityButton = NSButton()
    private let clipboardAccessLabel = NSTextField(labelWithString: "")
    private let clipboardAccessButton = NSButton()
    private let launchCheckbox = NSButton(checkboxWithTitle: "开机自启动", target: nil, action: nil)

    init(preferences: ClipboardPreferences, delegate: ClipboardSettingsDelegate,
         logger: LoggingService = AppContext.shared.logger) {
        self.preferences = preferences
        self.settingsDelegate = delegate
        self.logger = logger
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 600),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.title = "剪贴板设置"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.delegate = self
        window.contentView = buildContentView()
        refreshValues()
    }

    /// 打开设置窗（由菜单「剪贴板设置…」触发）
    func show() {
        refreshValues()
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: 界面构建

    private func buildContentView() -> NSView {
        configureControls()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

        stack.addArrangedSubview(sectionTitle("快捷键"))
        stack.addArrangedSubview(row("唤起面板", hotKeyRecorder))

        stack.addArrangedSubview(sectionTitle("采集与面板"))
        stack.addArrangedSubview(row("快速粘贴键", quickPasteCheckbox))
        stack.addArrangedSubview(row("采集模式", captureModePopup))
        stack.addArrangedSubview(row("面板位置", positionPopup))
        let heightRow = NSStackView(views: [heightSlider, heightLabel])
        heightRow.orientation = .horizontal
        heightRow.spacing = 8
        stack.addArrangedSubview(row("面板高度", heightRow))
        stack.addArrangedSubview(row("最大条数", maxItemsField))
        stack.addArrangedSubview(row("保留天数", retentionField))

        stack.addArrangedSubview(sectionTitle("忽略的应用（按 bundleID）"))
        ignoredStack.orientation = .vertical
        ignoredStack.alignment = .leading
        ignoredStack.spacing = 4
        stack.addArrangedSubview(indented(ignoredStack))
        ignoredInput.placeholderString = "com.example.app"
        ignoredInput.widthAnchor.constraint(equalToConstant: 240).isActive = true
        let addRow = NSStackView(views: [ignoredInput, makeButton("添加", #selector(addIgnoredApp))])
        addRow.orientation = .horizontal
        addRow.spacing = 8
        stack.addArrangedSubview(indented(addRow))

        stack.addArrangedSubview(sectionTitle("权限"))
        stack.addArrangedSubview(row("辅助功能权限", accessibilityLabel))
        stack.addArrangedSubview(row("", accessibilityButton))
        stack.addArrangedSubview(row("剪贴板访问", clipboardAccessLabel))
        stack.addArrangedSubview(row("", clipboardAccessButton))

        stack.addArrangedSubview(sectionTitle("通用"))
        stack.addArrangedSubview(row("开机自启动", launchCheckbox))
        return stack
    }

    private func configureControls() {
        hotKeyRecorder.combo = preferences.panelToggleHotKey
        hotKeyRecorder.onChange = { [weak self] combo in self?.applyHotKey(combo) }

        quickPasteCheckbox.target = self; quickPasteCheckbox.action = #selector(quickPasteChanged)
        for position in [ClipboardPanelPosition.mouseScreen, .primaryScreen, .mouseLocation] {
            positionPopup.addItem(withTitle: position.label)
            positionPopup.lastItem?.representedObject = position.rawValue
        }
        positionPopup.target = self; positionPopup.action = #selector(positionChanged)

        heightSlider.minValue = 200; heightSlider.maxValue = 400
        heightSlider.target = self; heightSlider.action = #selector(heightChanged)
        heightLabel.font = NSFont.systemFont(ofSize: 11); heightLabel.textColor = .secondaryLabelColor

        for field in [maxItemsField, retentionField] {
            field.alignment = .right
            field.target = self; field.action = #selector(limitsChanged)
            field.widthAnchor.constraint(equalToConstant: 80).isActive = true
        }
        for mode in [ClipboardCaptureMode.polling, .onDemand] {
            captureModePopup.addItem(withTitle: mode.label)
            captureModePopup.lastItem?.representedObject = mode.rawValue
        }
        captureModePopup.target = self; captureModePopup.action = #selector(captureModeChanged)

        accessibilityLabel.font = NSFont.systemFont(ofSize: 12)
        accessibilityButton.title = "前往系统设置"
        accessibilityButton.bezelStyle = .rounded
        accessibilityButton.target = self; accessibilityButton.action = #selector(requestAccessibility)
        clipboardAccessLabel.font = NSFont.systemFont(ofSize: 12)
        clipboardAccessButton.title = "前往系统设置"
        clipboardAccessButton.bezelStyle = .rounded
        clipboardAccessButton.target = self; clipboardAccessButton.action = #selector(requestClipboardAccess)

        launchCheckbox.target = self; launchCheckbox.action = #selector(launchAtStartupChanged)
    }

    private func sectionTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.boldSystemFont(ofSize: 13)
        return label
    }

    private func indented(_ view: NSView) -> NSView {
        let stack = NSStackView(views: [view])
        stack.orientation = .horizontal
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 132, bottom: 0, right: 0)
        return stack
    }

    private func row(_ title: String, _ control: NSView) -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.alignment = .centerY
        if title.isEmpty {
            stack.addArrangedSubview(indented(control))
        } else {
            let label = NSTextField(labelWithString: title)
            label.font = NSFont.systemFont(ofSize: 12)
            label.alignment = .right
            label.widthAnchor.constraint(equalToConstant: 120).isActive = true
            stack.addArrangedSubview(label)
            stack.addArrangedSubview(control)
        }
        return stack
    }

    private func makeButton(_ title: String, _ action: Selector) -> NSButton {
        NSButton(title: title, target: self, action: action)
    }

    // MARK: 取值与刷新

    private func refreshValues() {
        hotKeyRecorder.combo = preferences.panelToggleHotKey
        quickPasteCheckbox.state = preferences.quickPasteEnabled ? .on : .off
        positionPopup.selectItem(at: index(of: preferences.panelPosition.rawValue, in: positionPopup))
        heightSlider.doubleValue = preferences.panelHeight
        heightLabel.stringValue = "\(Int(preferences.panelHeight)) pt"
        maxItemsField.stringValue = "\(preferences.maxItems)"
        retentionField.stringValue = "\(preferences.retentionDays)"
        captureModePopup.selectItem(at: index(of: preferences.captureMode.rawValue, in: captureModePopup))
        launchCheckbox.state = UserDefaults.standard.bool(forKey: ClipboardPreferences.launchAtStartupKey) ? .on : .off
        reloadIgnoredApps()
        refreshPermissionStatus()
    }

    private func index(of rawValue: String, in popup: NSPopUpButton) -> Int {
        popup.itemArray.firstIndex { ($0.representedObject as? String) == rawValue } ?? 0
    }

    private func reloadIgnoredApps() {
        ignoredStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let bundleIDs = preferences.ignoredBundleIDs.sorted()
        guard !bundleIDs.isEmpty else {
            let empty = NSTextField(labelWithString: "（无）")
            empty.font = NSFont.systemFont(ofSize: 11)
            empty.textColor = .tertiaryLabelColor
            ignoredStack.addArrangedSubview(empty)
            return
        }
        for bundleID in bundleIDs {
            let label = NSTextField(labelWithString: bundleID)
            label.font = NSFont.systemFont(ofSize: 11)
            let remove = makeButton("移除", #selector(removeIgnoredApp(_:)))
            remove.controlSize = .mini
            remove.identifier = NSUserInterfaceItemIdentifier(bundleID)
            let row = NSStackView(views: [label, remove])
            row.orientation = .horizontal
            row.spacing = 8
            ignoredStack.addArrangedSubview(row)
        }
    }

    /// 权限状态：无权限时必须显式呈现并提供跳转（不得静默失败）
    private func refreshPermissionStatus() {
        let granted = settingsDelegate?.settingsAccessibilityGranted() ?? false
        accessibilityLabel.stringValue = granted ? "已授权" : "未授权（Paste Stack 的 ⌘V 监听不生效）"
        accessibilityLabel.textColor = granted ? .secondaryLabelColor : .systemOrange
        accessibilityButton.isHidden = granted

        var accessText = "未知"
        if #available(macOS 15.4, *) {
            switch NSPasteboard.general.accessBehavior {
            case .alwaysDeny: accessText = "已被拒绝（需在系统设置中允许）"
            case .alwaysAllow: accessText = "已允许"
            case .ask: accessText = "每次询问"
            default: accessText = "默认"
            }
        }
        clipboardAccessLabel.stringValue = accessText
        clipboardAccessLabel.textColor = accessText.hasPrefix("已被拒绝") ? .systemOrange : .secondaryLabelColor
    }

    // MARK: 动作

    /// 快捷键变更：注册失败不静默 —— 录制控件标红并保持原组合键
    private func applyHotKey(_ combo: HotKeyCombo) {
        let success = settingsDelegate?.settingsDidChangeHotKey(combo) ?? false
        hotKeyRecorder.isConflicted = !success
        if success { preferences.panelToggleHotKey = combo }
        logger.info("剪贴板唤起快捷键更新：\(combo.displayString)，注册成功=\(success)")
    }

    @objc private func quickPasteChanged() {
        preferences.quickPasteEnabled = quickPasteCheckbox.state == .on
    }

    @objc private func positionChanged() {
        guard let raw = positionPopup.selectedItem?.representedObject as? String,
              let position = ClipboardPanelPosition(rawValue: raw) else { return }
        preferences.panelPosition = position
    }

    @objc private func heightChanged() {
        preferences.panelHeight = heightSlider.doubleValue
        heightLabel.stringValue = "\(Int(heightSlider.doubleValue)) pt"
    }

    @objc private func limitsChanged() {
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

    @objc private func addIgnoredApp() {
        let bundleID = ignoredInput.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bundleID.isEmpty else { return }
        var ignored = preferences.ignoredBundleIDs
        ignored.insert(bundleID)
        preferences.ignoredBundleIDs = ignored
        ignoredInput.stringValue = ""
        reloadIgnoredApps()
        settingsDelegate?.settingsDidChangeIgnoredApps()
    }

    @objc private func removeIgnoredApp(_ sender: NSButton) {
        guard let bundleID = sender.identifier?.rawValue else { return }
        var ignored = preferences.ignoredBundleIDs
        ignored.remove(bundleID)
        preferences.ignoredBundleIDs = ignored
        reloadIgnoredApps()
        settingsDelegate?.settingsDidChangeIgnoredApps()
    }

    @objc private func requestAccessibility() {
        settingsDelegate?.settingsDidRequestAccessibilityPermission()
        refreshPermissionStatus()
    }

    @objc private func requestClipboardAccess() {
        settingsDelegate?.settingsDidRequestClipboardSettings()
    }

    @objc private func launchAtStartupChanged() {
        let enabled = launchCheckbox.state == .on
        UserDefaults.standard.set(enabled, forKey: ClipboardPreferences.launchAtStartupKey)
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            logger.error("开机自启动切换失败：\(error.localizedDescription)")
        }
    }
}
