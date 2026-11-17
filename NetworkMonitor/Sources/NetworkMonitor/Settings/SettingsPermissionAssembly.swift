import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 设置页的权限装配

/// 「系统权限」页工厂与功能页的权限注入 —— 从 `AppCoordinator+Settings` / `+Permissions` 收拢
///
/// 为什么单开一个文件：这两个方法是「把一个协议交给设置页」的纯装配，既不属于权限链路的
/// 运行时逻辑，也不属于设置窗口的页工厂表；放在 `AppCoordinator+*` 里会让那条族继续膨胀。
extension AppCoordinator {

    /// 设置页工厂：系统权限页（五类授权的唯一集中页）
    func makePermissionPane() -> SettingsPaneView {
        guard let permissions = permissionChain else {
            return SettingsUnavailablePane(section: .permissions,
                                           message: "系统权限状态尚未就绪，请稍后重开设置。")
        }
        return SettingsPermissionPane(permissions: permissions, logger: logger)
    }

    /// 截图页 + 屏幕录制就地简版（热键摘要来自 SnipController，未注册时给可读兜底）
    func makeCapturePane() -> SettingsPaneView {
        let pane = SettingsCapturePane(hotKeyDelegate: self,
                                       hotKeySummary: { [weak self] in
            self?.snipController?.hotKeySummary ?? "热键尚未注册"
        },
                                       notificationContext: settingsNotificationContext,
                                       logger: logger)
        return bindPermissionEntry(to: pane, kinds: [.screenCapture])
    }

    /// 通知与音效页：只注入快照（页头胶囊与授权状态行的文案同源），不另加权限卡
    func makeNotificationPane() -> SettingsPaneView {
        let pane = SettingsNotificationPane(preferences: notificationPreferences,
                                            player: soundPlayer,
                                            library: soundLibrary,
                                            service: notificationService,
                                            logger: logger)
        return bindPermissionEntry(to: pane, kinds: [])
    }

    /// 把权限快照注入功能页（就地简版的跳转 + 文案都读它），返回同一页便于链式返回
    ///
    /// - Parameter kinds: 就地显示的权限类别（空数组 = 只注入快照、不加卡，如通知页）
    @discardableResult
    func bindPermissionEntry<T: SettingsPaneView>(to pane: T,
                                                  kinds: [SystemPermissionKind]) -> T {
        guard let permissions = permissionChain else { return pane }
        pane.permissionSource = permissions
        pane.onOpenPermissions = { [weak self] in self?.settingsWindow?.show(section: .permissions) }
        if !kinds.isEmpty {
            pane.attachPermissionEntryCard(kinds: kinds)
        }
        return pane
    }
}
