import AppKit
import NetworkMonitorCore

// MARK: - 外观设置页

/// 外观设置 —— 主题、玻璃拟态与渲染帧率档
///
/// 三个旋钮都写 `AppearancePreferences`（禁止直读 UserDefaults），写完立刻发事件：
/// - 主题 / 玻璃 → `AppEvents.appearanceChanged`（面板重建材质并递归重绘）
/// - 渲染档 → `AppEvents.renderTierChanged` + `menuBarDisplayChanged`
///   （前者改中频节流与动效，后者让状态栏那个 Timer 按新周期重建）
///
/// 只发其中一个事件是本项目反复踩过的坑：事件发了但没人订阅 / 订阅了但不重建定时器，
/// 表现都是「设置页切了，实际没生效」。
final class SettingsAppearancePane: SettingsPaneView {

    private let preferences: AppearancePreferences
    private let logger: LoggingService

    private let themeRow = SettingsRowView(title: "主题",
                                           subtitle: "只改面系与玻璃配方，数据语义色（四族 / 状态）不随主题变")
    private let glassRow = SettingsRowView(title: "玻璃拟态",
                                           subtitle: "毛玻璃面板 + 卡片半透明底 + 顶部高光；关闭后回到不透明实色")
    private let tierRow = SettingsRowView(title: "渲染帧率",
                                          subtitle: "决定刷新节拍、动效与图表重采样上限")

    private let themeControl = NSPopUpButton(frame: .zero, pullsDown: false)
    private let glassSwitch = NSSwitch()
    private let tierControl = NSPopUpButton(frame: .zero, pullsDown: false)

    init(preferences: AppearancePreferences = AppearancePreferences(),
         logger: LoggingService = AppContext.shared.logger) {
        self.preferences = preferences
        self.logger = logger
        super.init(section: .appearance)
    }

    override func buildContent() {
        themeControl.addItems(withTitles: ThemeID.allCases.map { $0.displayName })
        themeControl.target = self
        themeControl.action = #selector(themeChanged)
        themeControl.setAccessibilityLabel("主题")

        glassSwitch.target = self
        glassSwitch.action = #selector(glassChanged)
        glassSwitch.setAccessibilityLabel("玻璃拟态")

        tierControl.addItems(withTitles: RenderTier.allCases.map { $0.displayName })
        tierControl.target = self
        tierControl.action = #selector(tierChanged)
        tierControl.setAccessibilityLabel("渲染帧率")

        themeRow.trailingStack.addArrangedSubview(themeControl)
        glassRow.trailingStack.addArrangedSubview(glassSwitch)
        tierRow.trailingStack.addArrangedSubview(tierControl)

        let themeCard = SettingsCardView()
        themeCard.addRow(themeRow)
        let glassCard = SettingsCardView()
        glassCard.addRow(glassRow)
        let tierCard = SettingsCardView()
        tierCard.addRow(tierRow)

        page.addCard(themeCard, sectionTitle: "主题")
        page.addCard(glassCard, sectionTitle: "材质")
        page.addCard(tierCard, sectionTitle: "性能")
        page.addNote("主题与玻璃对菜单面板、设置窗口即时生效；渲染帧率档同时决定菜单栏刷新节拍，"
                     + "选「省电」后面板收起时不再刷新（打开面板仍会强制刷新一次）。")
    }

    override func refresh() {
        let theme = preferences.themeID
        if let index = ThemeID.allCases.firstIndex(of: theme) {
            themeControl.selectItem(at: index)
        }
        themeRow.update(subtitle: theme.detail)

        glassSwitch.state = preferences.glassEnabled ? .on : .off
        glassRow.update(subtitle: preferences.glassOverride == nil
                        ? "当前跟随渲染档（省电档默认关闭）"
                        : (preferences.glassEnabled ? "已手动开启，换档不再自动关闭"
                                                    : "已手动关闭，换档不再自动开启"))

        let tier = preferences.renderTier
        if let index = RenderTier.allCases.firstIndex(of: tier) {
            tierControl.selectItem(at: index)
        }
        tierRow.update(subtitle: tier.detail)
    }

    // MARK: - 动作

    @objc private func themeChanged() {
        let index = themeControl.indexOfSelectedItem
        guard ThemeID.allCases.indices.contains(index) else { return }
        let theme = ThemeID.allCases[index]
        preferences.themeID = theme
        themeRow.update(subtitle: theme.detail)
        AppEvents.postAppearanceChanged()
        logger.info("设置页切换主题：\(theme.displayName)")
    }

    @objc private func glassChanged() {
        let enabled = glassSwitch.state == .on
        preferences.glassOverride = enabled
        refresh()
        AppEvents.postAppearanceChanged()
        logger.info("设置页切换玻璃：\(enabled ? "开" : "关")")
    }

    @objc private func tierChanged() {
        let index = tierControl.indexOfSelectedItem
        guard RenderTier.allCases.indices.contains(index) else { return }
        let tier = RenderTier.allCases[index]
        preferences.renderTier = tier
        refresh()
        // 两个事件都要发：renderTierChanged 改中频节流 / 动效 / 玻璃默认值，
        // menuBarDisplayChanged 让状态栏那个 Timer 按新周期重建
        AppEvents.postRenderTierChanged()
        AppEvents.postMenuBarDisplayChanged()
        logger.info("设置页切换渲染档：\(RenderTierLogic.summary(for: tier))")
    }
}
