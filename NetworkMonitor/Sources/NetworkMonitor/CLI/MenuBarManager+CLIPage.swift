import AppKit
import NetworkMonitorUI

// MARK: - 菜单面板的 CLI 页面入口

extension MenuBarManager {

    /// 为 CLI 页面输出打开菜单面板（已展开时复用，不 toggle 收起）
    ///
    /// 与状态栏点击的区别：点击是「开 → 关」的 toggle，CLI 要的是幂等的「确保打开」，
    /// 否则对已展开的面板再发一次命令会把用户眼前的页面关掉。
    @MainActor
    func showPanelForCLIPage(tabID: String?) {
        guard let button = statusItem.button else { return }
        if !panel.popover.isShown {
            panel.show(relativeTo: PanelAnchor.rect(for: button.bounds), of: button)
        }
        guard let tabID,
              let tab = MenuPanelTab.allCases.first(where: { $0.stableID == tabID }) else { return }
        panel.content.select(tab: tab)
    }
}
