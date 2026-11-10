import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 菜单面板根视图（分页偏好事件驱动）

/// 分页可见性 / 顺序变更后的重排 —— 从 `MenuPanelView.swift` 拆出（主文件接近单文件 15 KiB 上限）
///
/// 设置页写的是 `PanelTabPreferences` 存储，面板若只在 init 读一次，运行中改开关不会有任何反应
/// （用户口径「设置页禁止了某个功能，详情页展开之后没有消失」）。这里订阅 `AppEvents.panelTabsChanged`：
/// 重排分段、当前页被隐藏时切到第一个可见页、系统页二级详情收起，再让控制器重算高度。
extension MenuPanelView {

    /// 订阅分页偏好变更（面板构造末尾调用，只注册一次）
    func observePanelTabChanges() {
        panelTabsObserver = NotificationCenter.default.addObserver(
            forName: AppEvents.panelTabsChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.applyPanelTabPreferences()
            }
        }
    }

    /// 按最新偏好重排分段，并收拾当前页 / 二级详情 / 焦点与高度
    func applyPanelTabPreferences() {
        let visible = panelTabPreferences.orderedVisibleTabs
        // 兜底：偏好被手工写坏到一个可见页都没有时，分页条会是空白、键盘与点击全失效
        guard !visible.isEmpty else { return }
        tabBar.visibleTabs = visible

        let resolvedRaw = MenuBarDisplayLogic.resolvedTab(current: currentTab.rawValue,
                                                          visibleTabs: visible.map(\.rawValue))
        let resolved = MenuPanelTab(rawValue: resolvedRaw) ?? visible[0]
        let tabChanged = resolved != currentTab
        if tabChanged {
            currentTab = resolved
            applyTab()
            setFocus(index: nil)
        }
        // 系统页二级详情是覆盖式页面，所在分页被隐藏后必须收起，否则下次进来还停在详情
        if !visible.contains(.system) {
            systemPane.showOverview()
        }
        if tabChanged {
            delegate?.menuPanelViewDidSelectTab(self)
        }
        // 高度会随分段条与当前页变化：无论是否切页都通知控制器重算
        delegate?.menuPanelViewDidChangeContent(self)
    }
}
