import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 通知与音效设置页

/// 通知与音效 — 只放**全局项**：授权状态、应用内音量、音效库、恢复默认
///
/// 事件配置（开关 / 提示音 / 提醒方式 / 触觉）已按功能归属下沉到各事件自己的设置页：
/// 额度三行在「额度 Provider」，截图完成在「截图与贴图」，剪贴板动作在「剪贴板」，
/// 传输完成在「局域网互传」，面板展开收起在「通用」。
///
/// 为什么音效库不跟着拆：它是**资源管理**（导入 / 试听 / 重命名 / 删除 + 自定义列表），
/// 同时被多个事件引用，属于跨功能的公共资产，不是某一个功能的配置。
final class SettingsNotificationPane: SettingsPaneView {

    /// 放宽为 internal：扩展文件（音效库）要用同一份依赖
    let preferences: NotificationPreferences
    let player: NotificationSoundPlayer
    let library: NotificationSoundLibrary
    let service: any NotificationServicing
    let logger: LoggingService

    /// 授权状态行
    private let authDot = SettingsStatusDotView()
    private let authLabel = MenuPanelLabel.text("", font: SettingsTheme.rowSubtitleFont,
                                                color: SettingsTheme.textSecondary)
    // 放宽为 internal：音效库扩展文件（SettingsNotificationPane+SoundLibrary）要构建与刷新这些控件
    let volumeSlider = NSSlider()
    let volumeValueLabel = MenuPanelLabel.text("100%", font: SettingsTheme.rowValueFont,
                                               color: SettingsTheme.textSecondary)
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
        buildSoundLibraryCard()
        buildResetCard()
        page.addNote("各功能的通知与声音在那件事自己的设置页：额度提醒 / 额度重置 / 额度回升在「额度 Provider」，"
                     + "截图完成在「截图与贴图」，剪贴板动作在「剪贴板」，传输完成在「局域网互传」，"
                     + "面板展开收起在「通用」。")
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

    /// 恢复默认
    private func buildResetCard() {
        let row = SettingsRowView(title: "恢复默认",
                                  subtitle: "七类事件回到出厂配置，音量回到 100%，自定义音效保留")
        let reset = NSButton(title: "恢复默认", target: self, action: #selector(resetTapped))
        reset.bezelStyle = .rounded
        SettingsControlChrome.applyStandardHeight(to: reset)
        row.trailingStack.addArrangedSubview(reset)
        let card = SettingsCardView()
        card.addRow(row)
        page.addCard(card, sectionTitle: "重置")
    }

    // MARK: - 刷新

    override func refresh() {
        service.refreshAuthorizationState()
        renderAuthorizationState()
        refreshSoundLibrary()
    }

    /// 授权状态 → 状态点 + 文案 + 页头胶囊
    ///
    /// 三态只用主题那三种语义色（达标 / 告警 / 中性），不再引入红：
    /// - 已授权 → okInk
    /// - 已关闭（用户拒绝）→ warnInk（需要用户去系统设置打开）
    /// - 未决定（还没问过）→ ghost（中性，不是错误）
    private func renderAuthorizationState() {
        let state = service.authorizationState
        authLabel.stringValue = "\(state.label) · \(state.detail)"
        let tone = Self.tone(for: state)
        // 状态点与胶囊共用同一份语义映射（SettingsTheme.statusDotColor 就是 tone → 角色色）
        authDot.setColor(SettingsTheme.statusDotColor(tone))
        refreshStatusChip()
    }

    /// 页头胶囊：授权态 + 应用内音量
    ///
    /// 放宽为 internal：音效库扩展里拖动音量滑杆时也要同步胶囊（否则停在旧音量）。
    func refreshStatusChip() {
        let state = service.authorizationState
        let volume = "\(Int((preferences.inAppVolume * 100).rounded()))%"
        page.setStatusChip(SettingsStatusChip(subject: state.label,
                                             detail: "音量 \(volume)",
                                             tone: Self.tone(for: state)))
    }

    /// 授权态 → 胶囊 / 状态点语义（一处映射，两处显示不各判一遍）
    private static func tone(for state: NotificationAuthorizationState) -> SettingsStatusTone {
        switch state {
        case .authorized: return .ok
        case .denied: return .warn
        case .notDetermined: return .muted
        }
    }

    // MARK: - 动作

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
}
