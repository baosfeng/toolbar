import AppKit
import NetworkMonitorCore

// MARK: - 事件行依赖

/// 通知事件行的共享依赖 — 每个设置页注入一份
///
/// 四项依赖全部由组合根装配、且指向同一份 `NotificationPreferences`：
/// 配置在哪个页面改都写同一把键，所以「下沉」只换位置、不改读写路径。
@MainActor
struct SettingsNotificationEventContext {
    /// 事件配置（开关 / 声音 / 提醒方式 / 触觉）
    let preferences: NotificationPreferences
    /// 应用内音效播放（试听）
    let player: NotificationSoundPlayer
    /// 系统音效清单 + 自定义音效
    let library: NotificationSoundLibrary
    /// 系统通知出口（试听发真实通知、开关变化后同步音效副本）
    let service: any NotificationServicing
    /// 日志
    let logger: LoggingService

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
    }
}

// MARK: - 事件卡

/// 通知事件卡 — 一行四列：开关 / 提示音 / 提醒方式 / 触觉（行尾「试听」）
///
/// 为什么抽成组件：四列控件在五个设置页复用，复制五份必然分叉；
/// 这里只认事件列表——单事件页传一个、额度页传三个，同一条构造路径。
/// 提醒方式只对发系统通知的事件可用，其余置灰显示「—」，不让用户以为选了会生效。
@MainActor
final class SettingsNotificationEventCard: NSObject {

    /// 卡片本体 — 调用方 `page.addCard(card.card, sectionTitle: "通知与音效")`
    let card = SettingsCardView()

    /// 本页负责的事件（顺序即行顺序）
    private let events: [NotificationEvent]
    private let context: SettingsNotificationEventContext
    /// 是否在行尾放「试听」
    private let showsPreview: Bool

    /// 一行里的四个控件（键 = 事件）
    private struct RowControls {
        let toggle: NSSwitch
        let sound: NSPopUpButton
        let presentation: NSPopUpButton
        let haptic: NSPopUpButton
    }
    private var controls: [NotificationEvent: RowControls] = [:]

    /// - Parameters:
    ///   - events: 本页负责的事件（单事件页传一个，额度页传三个）
    ///   - context: 偏好 / 播放器 / 音效库 / 通知服务（同一份实例）
    ///   - showsPreview: 行尾是否给「试听」（默认给；关掉声音的场景可隐藏）
    init(events: [NotificationEvent],
         context: SettingsNotificationEventContext,
         showsPreview: Bool = true) {
        self.events = events
        self.context = context
        self.showsPreview = showsPreview
        super.init()
        buildRows()
        // 构建完立刻按偏好灌一次：首次进页与离屏快照都不保证走到 refresh，
        // 不灌就会出现「偏好是开、控件画成关」的假象（见踩坑记录「离屏快照看不出开关状态」）
        refresh()
    }

    // MARK: - 构建

    private func buildRows() {
        for event in events {
            let row = SettingsRowView(title: event.label)
            row.toolTip = event.detail

            let toggle = NSSwitch()
            toggle.identifier = Self.identifier(for: event)
            toggle.target = self
            toggle.action = #selector(enabledChanged(_:))
            toggle.setAccessibilityLabel(event.label)

            // 声音选项随音效库变化，这里先建空下拉，选项在 refresh 里按库重建
            let sound = makePopup(width: 112,
                                  items: nil,
                                  action: #selector(soundChanged(_:)),
                                  event: event,
                                  accessibility: "\(event.label)提示音")
            // 非系统通知事件没有提醒方式可选：占位一个「—」并置灰，
            // 不给一串选了也不生效的档位
            let presentation = makePopup(width: 100,
                                         items: event.postsSystemNotification
                                            ? NotificationPresentation.allCases.map(\.label)
                                            : ["—"],
                                         action: #selector(presentationChanged(_:)),
                                         event: event,
                                         accessibility: "\(event.label)提醒方式")
            presentation.isEnabled = event.postsSystemNotification
            presentation.toolTip = event.postsSystemNotification
                ? "横幅 / 声音 / 通知中心三档由应用决定，横幅样式由系统决定"
                : "该事件不发系统通知，提醒方式不生效"
            let haptic = makePopup(width: 66,
                                   items: NotificationHaptic.allCases.map(\.label),
                                   action: #selector(hapticChanged(_:)),
                                   event: event,
                                   accessibility: "\(event.label)触觉")

            row.trailingStack.addArrangedSubview(toggle)
            row.trailingStack.addArrangedSubview(sound)
            row.trailingStack.addArrangedSubview(presentation)
            row.trailingStack.addArrangedSubview(haptic)
            if showsPreview {
                let preview = SettingsLinkButton.make("试听", target: self,
                                                      action: #selector(previewTapped(_:)))
                preview.identifier = Self.identifier(for: event)
                preview.setAccessibilityLabel("\(event.label)试听")
                row.trailingStack.addArrangedSubview(preview)
            }
            card.addRow(row)
            controls[event] = RowControls(toggle: toggle, sound: sound,
                                          presentation: presentation, haptic: haptic)
        }
    }

    /// 下拉统一口径：小号、固定宽、identifier 存事件
    private func makePopup(width: CGFloat,
                           items: [String]?,
                           action: Selector,
                           event: NotificationEvent,
                           accessibility: String) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.controlSize = .small
        popup.font = SettingsStyle.rowSubtitleFont
        if let items { popup.addItems(withTitles: items) }
        popup.target = self
        popup.action = action
        popup.identifier = Self.identifier(for: event)
        popup.setAccessibilityLabel(accessibility)
        popup.widthAnchor.constraint(equalToConstant: width).isActive = true
        return popup
    }

    // MARK: - 刷新

    /// 同步控件显示（切页 / 窗口重新显示 / 音效库变化后调用）
    func refresh() {
        for event in events {
            guard let row = controls[event] else { continue }
            let config = context.preferences.config(for: event)
            row.toggle.state = config.enabled ? .on : .off
            rebuildSoundOptions(for: event, selected: config.sound)
            if event.postsSystemNotification,
               let index = NotificationPresentation.allCases.firstIndex(of: config.presentation) {
                row.presentation.selectItem(at: index)
            }
            row.presentation.isEnabled = event.postsSystemNotification
            if let index = NotificationHaptic.allCases.firstIndex(of: config.haptic) {
                row.haptic.selectItem(at: index)
            }
        }
    }

    /// 重建某个事件的声音下拉（选项集合随音效库变化）
    private func rebuildSoundOptions(for event: NotificationEvent,
                                     selected: NotificationSoundSelection) {
        guard let popup = controls[event]?.sound else { return }
        let options = soundOptions()
        popup.removeAllItems()
        popup.addItems(withTitles: options.map(\.title))
        if let index = options.firstIndex(where: { $0.selection == selected }) {
            popup.selectItem(at: index)
        } else {
            popup.selectItem(at: 0)
        }
    }

    /// 声音下拉的全部选项（跟随系统 / 静音 / 系统音效库 / 自定义）
    private func soundOptions() -> [(selection: NotificationSoundSelection, title: String)] {
        var options: [(NotificationSoundSelection, String)] = [
            (.systemDefault, "跟随系统"),
            (.silent, "静音"),
        ]
        for sound in context.library.systemSounds() {
            options.append((.systemSound(sound.name), "系统 · \(sound.title)"))
        }
        for file in context.library.customFiles() {
            options.append((.customFile(file), "自定义 · \(context.library.displayTitle(for: file))"))
        }
        return options
    }

    // MARK: - 动作

    @objc private func enabledChanged(_ sender: NSSwitch) {
        guard let event = event(for: sender) else { return }
        let enabled = sender.state == .on
        context.preferences.setEnabled(enabled, for: event)
        // 关掉发系统通知的事件后，通知目录里的音效副本该清就清
        context.service.syncInstalledSounds()
        context.logger.debug("事件 \(event.rawValue) 开关改为 \(enabled ? "开" : "关")")
    }

    @objc private func soundChanged(_ sender: NSPopUpButton) {
        guard let event = event(for: sender) else { return }
        let options = soundOptions()
        let index = sender.indexOfSelectedItem
        guard options.indices.contains(index) else { return }
        context.preferences.setSound(options[index].selection, for: event)
        context.service.syncInstalledSounds()
        context.logger.debug("事件 \(event.rawValue) 提示音改为 \(options[index].selection.storageValue)")
    }

    @objc private func presentationChanged(_ sender: NSPopUpButton) {
        guard let event = event(for: sender) else { return }
        let index = sender.indexOfSelectedItem
        guard NotificationPresentation.allCases.indices.contains(index) else { return }
        context.preferences.setPresentation(NotificationPresentation.allCases[index], for: event)
    }

    @objc private func hapticChanged(_ sender: NSPopUpButton) {
        guard let event = event(for: sender) else { return }
        let index = sender.indexOfSelectedItem
        guard NotificationHaptic.allCases.indices.contains(index) else { return }
        let level = NotificationHaptic.allCases[index]
        context.preferences.setHaptic(level, for: event)
        // 立刻震一下：手感只能当场试，选完没反应等于没选
        if level.isEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(HapticFeedback.pattern(for: level),
                                                             performanceTime: .now)
        }
    }

    @objc private func previewTapped(_ sender: NSButton) {
        guard let event = event(for: sender) else { return }
        preview(event: event)
    }

    /// 试听：发系统通知的事件走真实通知（能验证系统这一侧），其余走应用内音效
    private func preview(event: NotificationEvent) {
        let config = context.preferences.config(for: event)
        if event.postsSystemNotification, context.service.authorizationState == .authorized {
            context.service.post(NotificationMessage(event: event, title: "试听 · \(event.label)",
                                                    body: "这是「\(event.label)」的提醒效果"))
            return
        }
        // 未授权 / 非通知事件：直接播应用内提示音（跳过开关与去重，试听必须立刻有反馈）
        guard let cue = Self.previewCue(for: event) else { return }
        context.player.preview(selection: config.sound, cue: cue)
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

    // MARK: - 控件映射

    private static func identifier(for event: NotificationEvent) -> NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier(event.rawValue)
    }

    /// 按 identifier 反查事件（同页三行共用一个 action）
    private func event(for control: NSControl) -> NotificationEvent? {
        guard let raw = control.identifier?.rawValue else { return nil }
        return NotificationEvent(rawValue: raw)
    }

    // MARK: - 自证（仅 DEBUG）

    #if DEBUG
    /// 把偏好真值与控件显示态并排落盘（离屏快照看不出开关与下拉选中项）
    /// - Parameter tag: 文件名后缀，用所在页的 `fileSuffix`（一页一个文件）
    func debugLogStates(_ tag: String) {
        guard let path = ProcessInfo.processInfo.environment["NM_SNAPSHOT_DIR"], !path.isEmpty else {
            return
        }
        var lines: [String] = []
        for event in events {
            let pref = context.preferences.config(for: event)
            let row = controls[event]
            let ui = row?.toggle.state == .on
            let presentationUI: String
            if let row, row.presentation.isEnabled,
               NotificationPresentation.allCases.indices.contains(row.presentation.indexOfSelectedItem) {
                presentationUI = NotificationPresentation.allCases[row.presentation.indexOfSelectedItem].rawValue
            } else {
                presentationUI = "disabled"
            }
            lines.append("\(tag) \(event.rawValue) enabled=\(pref.enabled)/\(ui ? "on" : "off") "
                         + "sound=\(pref.sound.storageValue) presentation=\(pref.presentation.rawValue)/\(presentationUI) "
                         + "haptic=\(pref.haptic.rawValue) 一致=\(pref.enabled == ui)")
        }
        guard !lines.isEmpty else { return }
        let url = URL(fileURLWithPath: path, isDirectory: true)
            .appendingPathComponent("settings-notification-events-\(tag).txt")
        try? (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }
    #endif
}

// MARK: - 含事件卡的设置页

/// 含通知事件卡的设置页 — DEBUG 快照按这份协议一处取到事件卡（不必逐页 as?）
@MainActor
protocol SettingsNotificationEventHosting: AnyObject {
    /// 本页的事件卡
    var notificationCard: SettingsNotificationEventCard { get }
}
