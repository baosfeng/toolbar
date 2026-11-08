import AppKit
import NetworkMonitorCore

// MARK: - 通用设置页

/// 通用设置 — 启动行为、额度提醒与数值单位
///
/// 开关类写进既有偏好实现（`LaunchAtStartupService` / `BillingAlertPreferences`），
/// 与菜单栏齿轮菜单读同一份状态，避免两处勾选态不一致。
/// 「数值单位」写 `NumberUnitPreferences`（Core），切档后发 `AppEvents.numberUnitStyleChanged`，
/// 菜单面板据此立即重渲染，不用重启。
final class SettingsGeneralPane: SettingsPaneView {

    private let launchAtStartup: LaunchAtStartupService
    private let alertPreferences: BillingAlertPreferences
    private let unitPreferences: NumberUnitPreferences
    private let launchRow = SettingsRowView(title: "开机自启动",
                                            subtitle: "登录后自动启动 NetworkMonitor")
    private let alertRow = SettingsRowView(title: "额度阈值提醒",
                                           subtitle: "剩余跌破 5% / 4% / 3% / 2% / 1% 时发送系统通知")
    private let unitRow = SettingsRowView(title: "数值单位",
                                          subtitle: "Token 与额度数字的量级写法，切换后立即生效")
    private let launchSwitch = NSSwitch()
    private let alertSwitch = NSSwitch()
    private let unitControl = NSPopUpButton(frame: .zero, pullsDown: false)

    private let panelTabPreferences = PanelTabPreferences()
    private var tabToggles: [MenuPanelTab: NSSwitch] = [:]

    private let displayPreferences = MenuBarDisplayPreferences()
    private var metricToggles: [MenuBarMetric: NSSwitch] = [:]
    private var templateControl: NSSegmentedControl?

    init(launchAtStartup: LaunchAtStartupService = LaunchAtStartupService(),
         alertPreferences: BillingAlertPreferences = BillingAlertPreferences(),
         unitPreferences: NumberUnitPreferences = NumberUnitPreferences()) {
        self.launchAtStartup = launchAtStartup
        self.alertPreferences = alertPreferences
        self.unitPreferences = unitPreferences
        super.init(section: .general)
    }

    override func buildContent() {
        launchSwitch.target = self
        launchSwitch.action = #selector(launchChanged)
        launchSwitch.setAccessibilityLabel("开机自启动")
        alertSwitch.target = self
        alertSwitch.action = #selector(alertChanged)
        alertSwitch.setAccessibilityLabel("额度阈值提醒")

        unitControl.addItems(withTitles: NumberUnitStyle.allCases.map(\.title))
        unitControl.target = self
        unitControl.action = #selector(unitChanged)
        unitControl.setAccessibilityLabel("数值单位")

        launchRow.trailingStack.addArrangedSubview(launchSwitch)
        alertRow.trailingStack.addArrangedSubview(alertSwitch)
        unitRow.trailingStack.addArrangedSubview(unitControl)

        let launchCard = SettingsCardView()
        launchCard.addRow(launchRow)

        let alertCard = SettingsCardView()
        alertCard.addRow(alertRow)

        let unitCard = SettingsCardView()
        unitCard.addRow(unitRow)

        page.addCard(launchCard, sectionTitle: "启动")
        page.addCard(alertCard, sectionTitle: "额度提醒")
        page.addCard(unitCard, sectionTitle: "显示")
        buildPanelTabsCard()
        buildMenuBarMetricsCard()
        page.addNote("设置会立即生效；开机自启动依赖应用签名，未签名构建可能被系统拒绝。")
    }

    private func buildMenuBarMetricsCard() {
        let card = SettingsCardView()
        for metric in MenuBarMetric.allCases {
            let toggle = NSSwitch()
            toggle.target = self
            toggle.action = #selector(menuBarMetricToggled(_:))
            toggle.tag = metric.hashValue
            metricToggles[metric] = toggle
            let row = SettingsRowView(title: metric.displayName, subtitle: "菜单栏显示")
            row.trailingStack.addArrangedSubview(toggle)
            card.addRow(row)
        }
        // 模板快速切换
        let template = NSSegmentedControl(labels: ["默认", "性能", "Token", "网络", "全部"], trackingMode: .selectOne,
                                          target: self, action: #selector(menuBarTemplateChanged))
        template.tag = 0
        templateControl = template
        let templateRow = SettingsRowView(title: "快捷模板")
        templateRow.trailingStack.addArrangedSubview(template)
        card.addRow(templateRow)
        page.addCard(card, sectionTitle: "菜单栏显示")
    }

    @objc private func menuBarMetricToggled(_ sender: NSSwitch) {
        // 反查 metric
        for (metric, toggle) in metricToggles where toggle === sender {
            displayPreferences.setMetric(metric, enabled: sender.state == .on)
        }
    }

    @objc private func menuBarTemplateChanged() {
        let index = templateControl?.selectedSegment ?? 0
        let names = ["minimal", "performance", "token", "network", "full"]
        guard names.indices.contains(index) else { return }
        displayPreferences.applyTemplate(names[index])
        // 同步 toggle
        for (metric, toggle) in metricToggles {
            toggle.state = displayPreferences.enabledMetrics.contains(metric) ? .on : .off
        }
    }

    private func buildPanelTabsCard() {
        let card = SettingsCardView()
        for tab in MenuPanelTab.allCases {
            let toggle = NSSwitch()
            toggle.target = self
            toggle.action = #selector(panelTabToggled(_:))
            toggle.tag = tab.rawValue
            tabToggles[tab] = toggle
            let row = SettingsRowView(title: tab.title, subtitle: "显示面板分页；至少保留 1 个")
            row.trailingStack.addArrangedSubview(toggle)
            let up = SettingsLinkButton.make("上移", target: self, action: #selector(panelTabMoveUp(_:)))
            up.tag = tab.rawValue
            let down = SettingsLinkButton.make("下移", target: self, action: #selector(panelTabMoveDown(_:)))
            down.tag = tab.rawValue
            row.trailingStack.addArrangedSubview(up)
            row.trailingStack.addArrangedSubview(down)
            card.addRow(row)
        }
        page.addCard(card, sectionTitle: "面板分页")
    }

    @objc private func panelTabToggled(_ sender: NSSwitch) {
        guard let tab = MenuPanelTab(rawValue: sender.tag) else { return }
        panelTabPreferences.setVisible(sender.state == .on, for: tab)
    }

    @objc private func panelTabMoveUp(_ sender: NSButton) {
        guard let tab = MenuPanelTab(rawValue: sender.tag) else { return }
        panelTabPreferences.move(tab, offset: -1)
    }

    @objc private func panelTabMoveDown(_ sender: NSButton) {
        guard let tab = MenuPanelTab(rawValue: sender.tag) else { return }
        panelTabPreferences.move(tab, offset: 1)
    }

    override func refresh() {
        launchSwitch.state = launchAtStartup.isEnabled ? .on : .off
        alertSwitch.state = alertPreferences.isEnabled ? .on : .off
        let style = unitPreferences.style
        let styleIndex = NumberUnitStyle.allCases.firstIndex(of: style) ?? 0
        unitControl.selectItem(at: styleIndex)
        unitRow.update(subtitle: style.detailText)
        launchRow.update(subtitle: launchAtStartup.isEnabled
                         ? "登录后自动启动 NetworkMonitor"
                         : "当前未登记开机自启动")
        for (tab, toggle) in tabToggles {
            toggle.state = panelTabPreferences.visibleTabs.contains(tab) ? .on : .off
        }
        for (metric, toggle) in metricToggles {
            toggle.state = displayPreferences.enabledMetrics.contains(metric) ? .on : .off
        }
    }

    // MARK: - 动作

    @objc private func launchChanged() {
        let target = launchSwitch.state == .on
        let ok = launchAtStartup.setEnabled(target)
        if !ok {
            // 系统拒绝时回滚界面状态，避免显示已开启但实际没启动
            launchSwitch.state = target ? .off : .on
            launchRow.update(subtitle: "系统未允许开机自启动（需在系统设置中检查登录项）")
        } else {
            launchRow.update(subtitle: target
                             ? "登录后自动启动 NetworkMonitor"
                             : "当前未登记开机自启动")
        }
    }

    @objc private func alertChanged() {
        alertPreferences.setEnabled(alertSwitch.state == .on)
    }

    /// 数值单位切档：写偏好（只写用户显式选择的档）→ 发事件让面板立刻重渲染
    @objc private func unitChanged() {
        let index = unitControl.indexOfSelectedItem
        guard NumberUnitStyle.allCases.indices.contains(index) else { return }
        let style = NumberUnitStyle.allCases[index]
        unitPreferences.setStyle(style)
        unitRow.update(subtitle: style.detailText)
        AppEvents.postNumberUnitStyleChanged()
    }
}
