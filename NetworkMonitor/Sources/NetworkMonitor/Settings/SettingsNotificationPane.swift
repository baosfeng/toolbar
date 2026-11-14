import AppKit
import NetworkMonitorCore

// MARK: - 通知与音效设置页

/// 通知与音效 — 按事件配置声音、提醒方式与触控板手感
///
/// 版式：授权状态 → 事件表（开关）→ 提示音（每行一个下拉 + 试听）→ 提醒方式 →
/// 触控板手感 → 音效库（自定义上传，见扩展文件）→ 恢复默认。
///
/// 为什么把开关、声音、提醒方式拆成三张卡而不是「每个事件一大行」：
/// 设置窗内容宽只有 ~540pt，一行塞四个控件会让下拉被压到看不出内容；
/// 按维度成卡后每行只有「名称 + 一个控件」，六个事件也能一眼扫完。
final class SettingsNotificationPane: SettingsPaneView {

    /// 放宽为 internal：扩展文件（音效库）要用同一份依赖
    let preferences: NotificationPreferences
    let player: NotificationSoundPlayer
    let library: NotificationSoundLibrary
    let service: any NotificationServicing
    let logger: LoggingService

    /// 事件开关
    // 放宽为 internal：+Pickers 扩展文件（提示音 / 提醒方式 / 手感三张卡）要复用同一批控件
    var eventSwitches: [NotificationEvent: NSSwitch] = [:]
    /// 声音下拉
    var soundPopups: [NotificationEvent: NSPopUpButton] = [:]
    /// 提醒方式下拉
    var presentationPopups: [NotificationEvent: NSPopUpButton] = [:]
    /// 触觉下拉
    var hapticPopups: [NotificationEvent: NSPopUpButton] = [:]
    /// 授权状态行
    private let authDot = SettingsStatusDotView()
    private let authLabel = MenuPanelLabel.text("", font: SettingsStyle.rowSubtitleFont,
                                                color: .secondaryLabelColor)
    // 放宽为 internal：音效库扩展文件（SettingsNotificationPane+SoundLibrary）要构建与刷新这些控件
    let volumeSlider = NSSlider()
    let volumeValueLabel = MenuPanelLabel.text("100%", font: SettingsStyle.rowValueFont,
                                               color: .secondaryLabelColor)
    let uploadButton = NSButton(title: "上传…", target: nil, action: nil)
    let customListStack = NSStackView()

    init(preferences: NotificationPreferences,
         player: NotificationSoundPlayer,
         library: NotificationSoundLibrary,
         service: any NotificationServicing,
         logger: LoggingService = AppContext.shared.logger) {
        self.preferences = preferences
        self.player = player
        self.library = library
        self.service = service
        self.logger = logger
        super.init(section: .notifications)
    }

    // MARK: - 构建

    override func buildContent() {
        buildAuthorizationCard()
        buildEventCard()
        buildSoundCard()
        buildPresentationCard()
        buildHapticCard()
        buildSoundLibraryCard()
        buildResetCard()
        page.addNote("提醒方式与横幅样式：App 能决定的是「有没有声音」「前台要不要弹横幅」，"
                     + "横幅在屏幕上的位置和停留时长由系统「通知」设置决定，App 改不了。"
                     + "触觉档位对应系统三种触控板图案，不是数值强度。")
        refresh()
    }

    /// 授权状态卡：状态点 + 状态文案 + 去系统设置
    private func buildAuthorizationCard() {
        let row = SettingsRowView(title: "系统通知权限")
        let stack = NSStackView(views: [authDot, authLabel])
        stack.orientation = .horizontal
        stack.spacing = 6
        row.trailingStack.addArrangedSubview(stack)
        let openSettings = SettingsLinkButton.make("打开系统设置", target: self,
                                                   action: #selector(openSystemSettings))
        row.trailingStack.addArrangedSubview(openSettings)
        let card = SettingsCardView()
        card.addRow(row)
        page.addCard(card, sectionTitle: "权限")
    }

    /// 事件表：六个事件的开关
    private func buildEventCard() {
        let card = SettingsCardView()
        for event in NotificationEvent.allCases {
            let toggle = NSSwitch()
            toggle.target = self
            toggle.action = #selector(eventToggled(_:))
            toggle.tag = NotificationEvent.allCases.firstIndex(of: event) ?? 0
            toggle.setAccessibilityLabel(event.label)
            eventSwitches[event] = toggle
            let row = SettingsRowView(title: event.label,
                                      subtitle: event.detail)
            row.trailingStack.addArrangedSubview(toggle)
            card.addRow(row)
        }
        page.addCard(card, sectionTitle: "事件")
    }

    /// 恢复默认
    private func buildResetCard() {
        let row = SettingsRowView(title: "恢复默认",
                                  subtitle: "六个事件回到出厂配置，音量回到 100%，自定义音效保留")
        let reset = NSButton(title: "恢复默认", target: self, action: #selector(resetTapped))
        reset.bezelStyle = .rounded
        row.trailingStack.addArrangedSubview(reset)
        let card = SettingsCardView()
        card.addRow(row)
        page.addCard(card, sectionTitle: "重置")
    }

    // MARK: - 刷新

    override func refresh() {
        service.refreshAuthorizationState()
        renderAuthorizationState()
        for event in NotificationEvent.allCases {
            let config = preferences.config(for: event)
            eventSwitches[event]?.state = config.enabled ? .on : .off
            rebuildSoundPopup(event)
            if let popup = presentationPopups[event],
               let index = NotificationPresentation.allCases.firstIndex(of: config.presentation) {
                popup.selectItem(at: index)
            }
            if let popup = hapticPopups[event],
               let index = NotificationHaptic.allCases.firstIndex(of: config.haptic) {
                popup.selectItem(at: index)
            }
        }
        refreshSoundLibrary()
    }

    /// 授权状态 → 状态点 + 文案
    private func renderAuthorizationState() {
        let state = service.authorizationState
        authLabel.stringValue = "\(state.label) · \(state.detail)"
        switch state {
        case .authorized: authDot.setColor(.systemGreen)
        case .notDetermined: authDot.setColor(.systemOrange)
        case .denied: authDot.setColor(.systemRed)
        }
    }

    // MARK: - 动作

    @objc private func eventToggled(_ sender: NSSwitch) {
        guard let event = event(for: sender) else { return }
        preferences.setEnabled(sender.state == .on, for: event)
        // 关掉一个发系统通知的事件后，通知目录里的副本该清就清
        service.syncInstalledSounds()
    }

    // 放宽为 internal：+Pickers 扩展文件的「试听」按钮指向这个 action
    @objc func previewTapped(_ sender: NSButton) {
        guard let event = event(for: sender) else { return }
        preview(event: event)
    }

    /// 试听：发系统通知的事件走真实通知（能验证系统这一侧），其余走应用内音效
    func preview(event: NotificationEvent) {
        let config = preferences.config(for: event)
        if event.postsSystemNotification, service.authorizationState == .authorized {
            service.post(NotificationMessage(event: event, title: "试听 · \(event.label)",
                                             body: "这是「\(event.label)」的提醒效果"))
            return
        }
        // 未授权 / 非通知事件：直接播应用内提示音（跳过开关与去重，试听必须立刻有反馈）
        guard let cue = Self.previewCue(for: event) else { return }
        player.preview(selection: config.sound, cue: cue)
    }

    /// 事件 → 试听用的 cue（系统通知事件回落到各自的默认 cue）
    static func previewCue(for event: NotificationEvent) -> NotificationCue? {
        switch event {
        case .billingAlert: return .billingAlert
        case .billingWindowReset: return .billingWindowReset
        case .billingRecovery: return .billingRecovery
        case .transferFinished: return .transferFinished
        case .snipCaptured: return .snipCapture
        case .clipboardAction: return .copy
        case .panelToggle: return .panelToggle
        }
    }

    @objc private func resetTapped() {
        preferences.resetToDefaults()
        service.syncInstalledSounds()
        refresh()
        logger.info("通知与音效已恢复默认")
    }

    @objc private func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
        if let url { NSWorkspace.shared.open(url) }
    }

    // MARK: - 控件映射

    /// 按 tag 反查事件（六行控件共用一个 action；+Pickers 扩展文件也用）
    func event(for control: NSControl) -> NotificationEvent? {
        let cases = NotificationEvent.allCases
        guard cases.indices.contains(control.tag) else { return nil }
        return cases[control.tag]
    }

    /// 下拉 → 声音选择（+Pickers 扩展文件也用）
    func selectedSound(for popup: NSPopUpButton) -> NotificationSoundSelection? {
        let index = popup.indexOfSelectedItem
        let options = soundOptions()
        guard options.indices.contains(index) else { return nil }
        return options[index].selection
    }

    // MARK: - 自证（仅 DEBUG）

    #if DEBUG
    /// 把六个事件的开关勾选态与偏好真值并排落盘（离屏快照看不出 NSSwitch 的 on/off）
    func debugLogControlStates(_ tag: String) {
        var lines: [String] = []
        for event in NotificationEvent.allCases {
            let pref = preferences.config(for: event)
            let ui = eventSwitches[event]?.state == .on
            lines.append("\(tag) \(event.rawValue) enabled=\(pref.enabled)/\(ui ? "on" : "off") "
                         + "sound=\(pref.sound.storageValue) "
                         + "presentation=\(pref.presentation.rawValue) haptic=\(pref.haptic.rawValue)")
        }
        guard let path = ProcessInfo.processInfo.environment["NM_SNAPSHOT_DIR"], !path.isEmpty else { return }
        let url = URL(fileURLWithPath: path, isDirectory: true)
            .appendingPathComponent("settings-notifications-states.txt")
        try? (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }
    #endif
}