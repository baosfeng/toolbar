import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 应用协调器（系统权限）

/// 权限链路装配 —— 状态读取收敛到 `SystemPermissionCenter`，刷新时机在这里统一接线
///
/// 用户口径「权限都设置好了还显示没权限」的根因是「只在页面构建时读一次」；
/// 修法是把刷新挂到三个必然会经过的时刻：应用激活（中心内部监听）、面板打开、
/// 设置页「检测状态」。三处都只调同一个 `refresh()`，各页只读同一份快照，口径不会分叉。
extension AppCoordinator {

    /// 装配权限链路 + 启动期登记（异步，不阻塞首帧）
    ///
    /// 必须在 `setupSnip()` 之后：屏幕录制状态直接读捕获服务的 preflight，
    /// 而 preflight 只「查」不登记（把应用列进清单只发生在用户点「授权」时）。
    func setupPermissions() {
        guard let captureService = snipController?.captureService else {
            logger.warning("权限链路未装配：截图捕获服务尚未就绪")
            return
        }
        let center = SystemPermissionCenter(captureService: captureService, logger: logger)
        let chain = SystemPermissionChain(center: center, stack: clipboardStack, logger: logger)
        permissionChain = chain
        // 启动只静默读取：不弹系统框、不请求授权（弹框留给用户点「授权」那一刻）
        chain.bootstrap()
    }
}
// MARK: - 剪贴板设置页的权限回调

/// 协议里的三个权限入口 —— 转发到统一权限链，不再直接问 Paste Stack
///
/// 设置页已改读 `SystemPermissionProviding` 快照，这三个方法目前没有调用方；
/// 协议文件（`ClipboardSettingsDelegate`）不在本轮 scope，先把实现口径指向同一份快照，
/// 不留下第二条读取路径。放在这里而不是剪贴板设置文件里，是为了让「权限」这条链路
/// 的实现聚在一起，也不把组合根的装配文件撑大。
extension AppCoordinator {

    func settingsAccessibilityGranted() -> Bool {
        permissionChain?.snapshot.accessibility == .granted
    }

    func settingsDidRequestAccessibilityPermission() {
        permissionChain?.request(.accessibility)
    }

    func settingsDidRequestClipboardSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") else { return }
        NSWorkspace.shared.open(url)
    }
}
// MARK: - 剪贴板面板入口

/// 唤出剪贴板面板 —— 两个入口（状态栏菜单、全局热键）共用这一处
///
/// 先重读权限再展示：面板页脚的辅助功能入口与设置页读同一份快照，
/// 用户刚在系统设置勾完，这一次打开就该是绿的（不用重启应用）。
extension AppCoordinator {

    func toggleClipboardPanel() {
        permissionChain?.refresh()
        clipboardPanel.toggle()
    }
}
