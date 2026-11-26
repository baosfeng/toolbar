import AppKit
import NetworkMonitorCore

// MARK: - 通用设置页（可排序两块 + 显示方式卡接线）

/// 从主文件拆出的「可排序」部分 —— 守住单文件 15 KiB 门禁
///
/// 两块可排序卡片：
/// - 菜单栏指标 → `SettingsOrderKey.menuBarMetrics`（改完发 `AppEvents.menuBarDisplayChanged`，状态栏立刻重排）
/// - 面板分页 → `SettingsOrderKey.panelTabs`（改完发 `AppEvents.panelTabsChanged`，面板分段条重排）
///
/// 「菜单栏显示方式」不可排序，已独立成卡 `SettingsMenuBarDisplayStyleCard`
/// （模板 / 密度 / 单位 / **标签** / 布局 + 逐项自定义），本文件只负责 addCard 与 refresh。
extension SettingsGeneralPane {

    // MARK: - 构建

    /// 追加三块（在 `buildContent` 里调用）
    func buildOrderableCards() {
        buildMenuBarMetricsCard()
        page.addCard(displayStyleCard.card, sectionTitle: "菜单栏显示方式")
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

    // MARK: - 刷新

    /// 指标开关的勾选态同步（模板切换后由显示方式卡回调，`refresh()` 也走这里）
    func syncMetricToggles() {
        for (toggle, metric) in metricByToggle {
            toggle.state = displayPreferences.enabledMetrics.contains(metric) ? .on : .off
        }
    }

    /// 把偏好灌回可排序两块与显示方式卡（`refresh()` 里调用）
    func refreshOrderableControls() {
        syncMetricToggles()
        for (toggle, tab) in tabByToggle {
            toggle.state = panelTabPreferences.visibleTabs.contains(tab) ? .on : .off
        }
        displayStyleCard.refresh()
    }

    /// 菜单栏单位行副标题 —— 直接写出各档的实际效果，避免「选了自定义却看不出变化」
    static func menuBarUnitSubtitle(_ style: MenuBarUnitStyle) -> String {
        switch style {
        case .short: return "紧凑写法，如 1.2M"
        case .full: return "带空格全称，如 1.2 MB/s"
        case .custom: return "自定义单位表暂未提供，当前按紧凑写法显示"
        }
    }

    // MARK: - 动作（菜单栏指标 / 面板分页）

    @objc private func menuBarMetricToggled(_ sender: NSSwitch) {
        guard let metric = metricByToggle[sender] else { return }
        displayPreferences.setMetric(metric, enabled: sender.state == .on)
        // 至少保留一项：存储侧已拦，这里把界面勾选态拉回真实值
        sender.state = displayPreferences.enabledMetrics.contains(metric) ? .on : .off
        AppEvents.postMenuBarDisplayChanged()
    }

    @objc private func panelTabToggled(_ sender: NSSwitch) {
        guard let tab = tabByToggle[sender] else { return }
        panelTabPreferences.setVisible(sender.state == .on, for: tab)
        sender.state = panelTabPreferences.visibleTabs.contains(tab) ? .on : .off
        AppEvents.postPanelTabsChanged()
    }
}
