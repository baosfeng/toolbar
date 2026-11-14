import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

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
        themeControl.font = SettingsTheme.rowTitleFont
        SettingsControlChrome.applyStandardHeight(to: themeControl)

        glassSwitch.target = self
        glassSwitch.action = #selector(glassChanged)
        glassSwitch.setAccessibilityLabel("玻璃拟态")

        tierControl.addItems(withTitles: RenderTier.allCases.map { $0.displayName })
        tierControl.target = self
        tierControl.action = #selector(tierChanged)
        tierControl.setAccessibilityLabel("渲染帧率")
        tierControl.font = SettingsTheme.rowTitleFont
        SettingsControlChrome.applyStandardHeight(to: tierControl)

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

        refreshStatusChip()
    }

    /// 页头胶囊：主题名 + 渲染档名（两个都是本页正在显示的真实偏好值）
    ///
    /// 单独成方法是因为「切主题」这条动作只写偏好 + 发事件，不走整页 refresh，
    /// 不在这里补一次的话页头会停在旧主题名上。
    private func refreshStatusChip() {
        page.setStatusChip(SettingsStatusChip(subject: preferences.themeID.displayName,
                                              detail: preferences.renderTier.displayName,
                                              tone: .ok))
    }

    #if DEBUG
    /// 把三项的**偏好真值 / 控件勾选态**并排落盘
    ///
    /// 为什么需要：`NSSwitch` 的 on/off 在离屏渲染里几乎不可辨（见踩坑记录
    /// 「离屏快照看不出开关状态」——设置页四行开关在图里全画成浅灰关态，
    /// 但偏好与控件其实都是开）。因此「外观」页快照的开关状态以本文件为准，
    /// 图只用于看版式。
    func debugLogAppearanceControlStates(_ tag: String) {
        let themePref = preferences.themeID.displayName
        let themeShown = ThemeID.allCases.indices.contains(themeControl.indexOfSelectedItem)
            ? ThemeID.allCases[themeControl.indexOfSelectedItem].displayName : "?"
        let glassPref = preferences.glassEnabled
        let glassShown = glassSwitch.state == .on
        let tierPref = preferences.renderTier.displayName
        let tierShown = RenderTier.allCases.indices.contains(tierControl.indexOfSelectedItem)
            ? RenderTier.allCases[tierControl.indexOfSelectedItem].displayName : "?"
        let overrideText = preferences.glassOverride == nil
            ? "跟随档位" : (preferences.glassOverride == true ? "手动开" : "手动关")
        let matches = themePref == themeShown && glassPref == glassShown && tierPref == tierShown
        let line = "[\(tag)] 主题=\(themePref)/\(themeShown) "
            + "玻璃=\(glassPref)/\(glassShown ? "on" : "off")（\(overrideText)） "
            + "档位=\(tierPref)/\(tierShown) 一致=\(matches) "
            + "玻璃配方：填充alpha=\(ThemeStyle.cardFillAlpha) "
            + "高光=\(ThemeStyle.highlightAlpha) 描边=\(ThemeStyle.strokeAlpha) "
            + "面板底=\(ThemeStyle.glassEnabled ? "NSGlassEffectView" : "纯实色")"
        guard let path = ProcessInfo.processInfo.environment["NM_SNAPSHOT_DIR"], !path.isEmpty else { return }
        let url = URL(fileURLWithPath: path, isDirectory: true)
            .appendingPathComponent("settings-appearance-states.txt")
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        try? (existing + line + "\n").write(to: url, atomically: true, encoding: .utf8)
    }
    #endif

    // MARK: - 动作

    @objc private func themeChanged() {
        let index = themeControl.indexOfSelectedItem
        guard ThemeID.allCases.indices.contains(index) else { return }
        let theme = ThemeID.allCases[index]
        preferences.themeID = theme
        themeRow.update(subtitle: theme.detail)
        refreshStatusChip()
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
