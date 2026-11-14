import AppKit
import NetworkMonitorCore

// MARK: - 通用设置页（可排序三块：菜单栏指标 / 面板分页 / 显示方式）

/// 从主文件拆出的「可排序」部分 —— 守住单文件 15 KiB 门禁
///
/// 三张卡片的顺序偏好：
/// - 菜单栏指标 → `SettingsOrderKey.menuBarMetrics`（改完发 `AppEvents.menuBarDisplayChanged`，状态栏立刻重排）
/// - 面板分页 → `SettingsOrderKey.panelTabs`（改完发 `AppEvents.panelTabsChanged`，面板分段条重排）
/// - 显示方式（模板 / 密度 / 单位 / 布局 / 间隔）不可排序，单独一卡，避免和可排序行混放
extension SettingsGeneralPane {

    // MARK: - 构建

    /// 追加三张卡片（在 `buildContent` 里调用）
    func buildOrderableCards() {
        buildMenuBarMetricsCard()
        buildMenuBarDisplayStyleCard()
        buildPanelTabsCard()
    }

    /// 菜单栏指标 —— 可排序卡片（顺序即状态栏上屏顺序）
    private func buildMenuBarMetricsCard() {
        let ordered = SettingsOrderedCardView(orderKey: SettingsOrderKey.menuBarMetrics,
                                              defaultOrder: MenuBarMetric.defaultOrderIDs,
                                              storage: storage,
                                              onChange: { _ in AppEvents.postMenuBarDisplayChanged() })
        for metric in MenuBarMetric.allCases {
            let toggle = NSSwitch()
            toggle.target = self
            toggle.action = #selector(menuBarMetricToggled(_:))
            toggle.setAccessibilityLabel(metric.displayName)
            metricByToggle[toggle] = metric

            let row = SettingsRowView(title: metric.displayName)
            row.trailingStack.addArrangedSubview(toggle)
            ordered.addRow(id: metric.rawValue,
                           row: row,
                           accessibilityPrefix: metric.displayName) { [weak row] position in
                row?.update(subtitle: "第 \(position) 项")
            }
        }
        ordered.finish()
        metricsOrderCard = ordered
        page.addCard(ordered.card,
                     sectionTitle: "菜单栏指标（顺序即上屏顺序）",
                     trailingAccessory: ordered.resetButton)
    }

    /// 面板分页 —— 可排序卡片（顺序即数字键与左右循环顺序）
    private func buildPanelTabsCard() {
        let ordered = SettingsOrderedCardView(orderKey: SettingsOrderKey.panelTabs,
                                              defaultOrder: PanelTabPreferences.defaultOrder.map(\.stableID),
                                              storage: storage,
                                              onChange: { _ in AppEvents.postPanelTabsChanged() })
        for tab in MenuPanelTab.allCases {
            let toggle = NSSwitch()
            toggle.target = self
            toggle.action = #selector(panelTabToggled(_:))
            toggle.setAccessibilityLabel(tab.title)
            tabByToggle[toggle] = tab

            let row = SettingsRowView(title: tab.title)
            row.trailingStack.addArrangedSubview(toggle)
            ordered.addRow(id: tab.stableID,
                           row: row,
                           accessibilityPrefix: tab.title) { [weak row] position in
                row?.update(subtitle: "第 \(position) 项 · 至少保留 1 个")
            }
        }
        ordered.finish()
        panelTabsOrderCard = ordered
        page.addCard(ordered.card,
                     sectionTitle: "面板分页（顺序即切换顺序）",
                     trailingAccessory: ordered.resetButton)
    }

    /// 菜单栏显示方式 —— 普通卡片（模板 / 密度 / 单位 / 布局 / 间隔，全部是单选，无顺序语义）
    private func buildMenuBarDisplayStyleCard() {
        let card = SettingsCardView()

        let template = NSSegmentedControl(labels: Self.templateTitles, trackingMode: .selectOne,
                                          target: self, action: #selector(menuBarTemplateChanged))
        template.tag = 0
        templateControl = template
        let templateRow = SettingsRowView(title: "快捷模板", subtitle: "只改显示哪些指标，不改上面排好的顺序")
        templateRow.trailingStack.addArrangedSubview(template)
        card.addRow(templateRow)

        densityControl.addItems(withTitles: MenuBarDensity.allCases.map(\.rawValue))
        densityControl.target = self
        densityControl.action = #selector(menuBarDensityChanged)
        let densityRow = SettingsRowView(title: "密度")
        densityRow.trailingStack.addArrangedSubview(densityControl)
        card.addRow(densityRow)

        // 菜单栏单位档：custom 目前没有自定义单位表（按 short 回落），
        // 直接标在标题里，避免用户选了「自定义」却看不到任何变化
        unitControl2.addItems(withTitles: MenuBarUnitStyle.allCases.map(\.title))
        unitControl2.target = self
        unitControl2.action = #selector(menuBarUnitChanged)
        unit2Row.trailingStack.addArrangedSubview(unitControl2)
        card.addRow(unit2Row)

        layoutControl.addItems(withTitles: MenuBarLayout.allCases.map(\.rawValue))
        layoutControl.target = self
        layoutControl.action = #selector(menuBarLayoutChanged)
        let layoutRow = SettingsRowView(title: "布局")
        layoutRow.trailingStack.addArrangedSubview(layoutControl)
        card.addRow(layoutRow)

        intervalControl.addItems(withTitles: ["1s", "2s", "5s"])
        intervalControl.target = self
        intervalControl.action = #selector(menuBarIntervalChanged)
        let intervalRow = SettingsRowView(title: "间隔")
        intervalRow.trailingStack.addArrangedSubview(intervalControl)
        card.addRow(intervalRow)

        page.addCard(card, sectionTitle: "菜单栏显示方式")
    }

    // MARK: - 刷新

    /// 把偏好灌回可排序三块的控件（`refresh()` 里调用）
    func refreshOrderableControls() {
        for (toggle, metric) in metricByToggle {
            toggle.state = displayPreferences.enabledMetrics.contains(metric) ? .on : .off
        }
        for (toggle, tab) in tabByToggle {
            toggle.state = panelTabPreferences.visibleTabs.contains(tab) ? .on : .off
        }
        // 模板选中段回灌：点完模板再进设置页时不能显示成「默认」（-1 = 与应用内模板名不匹配）
        if let templateControl {
            templateControl.selectedSegment = Self.templateNames.firstIndex(of: displayPreferences.template) ?? -1
        }
        if let i = MenuBarDensity.allCases.firstIndex(of: displayPreferences.density) { densityControl.selectItem(at: i) }
        if let i = MenuBarUnitStyle.allCases.firstIndex(of: displayPreferences.unitStyle) { unitControl2.selectItem(at: i) }
        unit2Row.update(subtitle: Self.menuBarUnitSubtitle(displayPreferences.unitStyle))
        if let i = MenuBarLayout.allCases.firstIndex(of: displayPreferences.layout) { layoutControl.selectItem(at: i) }
        let vals: [TimeInterval] = [1, 2, 5]
        if let i = vals.firstIndex(of: displayPreferences.refreshInterval) { intervalControl.selectItem(at: i) }
    }

    /// 菜单栏单位行副标题 —— 直接写出各档的实际效果，避免「选了自定义却看不出变化」
    static func menuBarUnitSubtitle(_ style: MenuBarUnitStyle) -> String {
        switch style {
        case .short: return "紧凑写法，如 1.2M"
        case .full: return "带空格全称，如 1.2 MB/s"
        case .custom: return "自定义单位表暂未提供，当前按紧凑写法显示"
        }
    }

    // MARK: - 动作（菜单栏显示方式）

    @objc private func menuBarDensityChanged() {
        let idx = densityControl.indexOfSelectedItem
        guard MenuBarDensity.allCases.indices.contains(idx) else { return }
        displayPreferences.density = MenuBarDensity.allCases[idx]
        AppEvents.postMenuBarDisplayChanged()
    }

    @objc private func menuBarUnitChanged() {
        let idx = unitControl2.indexOfSelectedItem
        guard MenuBarUnitStyle.allCases.indices.contains(idx) else { return }
        displayPreferences.unitStyle = MenuBarUnitStyle.allCases[idx]
        unit2Row.update(subtitle: Self.menuBarUnitSubtitle(displayPreferences.unitStyle))
        AppEvents.postMenuBarDisplayChanged()
    }

    @objc private func menuBarLayoutChanged() {
        let idx = layoutControl.indexOfSelectedItem
        guard MenuBarLayout.allCases.indices.contains(idx) else { return }
        displayPreferences.layout = MenuBarLayout.allCases[idx]
        AppEvents.postMenuBarDisplayChanged()
    }

    @objc private func menuBarIntervalChanged() {
        let titles = ["1s", "2s", "5s"]
        let idx = intervalControl.indexOfSelectedItem
        guard titles.indices.contains(idx) else { return }
        let vals: [TimeInterval] = [1, 2, 5]
        displayPreferences.refreshInterval = vals[idx]
        AppEvents.postMenuBarDisplayChanged()
    }

    // MARK: - 动作（菜单栏指标 / 面板分页）

    @objc private func menuBarMetricToggled(_ sender: NSSwitch) {
        guard let metric = metricByToggle[sender] else { return }
        displayPreferences.setMetric(metric, enabled: sender.state == .on)
        // 至少保留一项：存储侧已拦，这里把界面勾选态拉回真实值
        sender.state = displayPreferences.enabledMetrics.contains(metric) ? .on : .off
        AppEvents.postMenuBarDisplayChanged()
    }

    @objc private func menuBarTemplateChanged() {
        let index = templateControl?.selectedSegment ?? 0
        guard Self.templateNames.indices.contains(index) else { return }
        displayPreferences.applyTemplate(Self.templateNames[index])
        // 同步 toggle（模板只改显示集合，顺序保持用户排布）
        for (toggle, metric) in metricByToggle {
            toggle.state = displayPreferences.enabledMetrics.contains(metric) ? .on : .off
        }
        AppEvents.postMenuBarDisplayChanged()
    }

    @objc private func panelTabToggled(_ sender: NSSwitch) {
        guard let tab = tabByToggle[sender] else { return }
        panelTabPreferences.setVisible(sender.state == .on, for: tab)
        sender.state = panelTabPreferences.visibleTabs.contains(tab) ? .on : .off
        AppEvents.postPanelTabsChanged()
    }
}
