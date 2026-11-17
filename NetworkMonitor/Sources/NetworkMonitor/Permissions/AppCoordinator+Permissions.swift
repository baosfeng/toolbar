import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 应用协调器（系统权限）

/// 权限链路装配 —— 状态读取收敛到 `SystemPermissionCenter`，刷新时机在这里统一接线
///
/// 用户口径「权限都设置好了还显示没权限」的根因是「只在页面构建时读一次」；
/// 修法是把刷新挂到三个必然会经过的时刻：应用激活（中心内部监听）、面板打开、
/// 设置页「检测状态」。三处都只调同一个 `refresh()`，各页只读同一份快照，口径不会分叉。
///
/// 设置页侧的装配（权限页工厂 / 功能页注入）在 `SettingsPermissionAssembly`：
/// 那是「把协议交给页面」，不是链路本身。
extension AppCoordinator {

    /// 装配权限链路 + 启动期登记（异步，不阻塞首帧）
    ///
    /// 必须在 `setupSnip()` 之后：屏幕录制状态直接读捕获服务的 preflight，
    /// 而 preflight 只「查」不登记（把应用列进清单只发生在用户点「授权」时）。
    /// 通知与登录项走各自的公共服务（`NotificationServicing` 缓存 / `SMAppService` 状态），
    /// 中心只读它们，不自己 new 第二份。
    func setupPermissions() {
        guard let captureService = snipController?.captureService else {
            logger.warning("权限链路未装配：截图捕获服务尚未就绪")
            return
        }
        let center = SystemPermissionCenter(captureService: captureService,
                                            notifications: notificationService,
                                            launchAtStartup: LaunchAtStartupService(logger: logger),
                                            logger: logger)
        let chain = SystemPermissionChain(center: center, stack: clipboardStack, logger: logger)
        permissionChain = chain
        // 两处旧的自拼深链 / 重复 preflight 改由中心统一出口：
        // 面板页脚的辅助功能按钮与截图引导都只拿到协议，不自己拼 URL
        clipboardStack?.onRequestAccessibility = { [weak chain] in
            chain?.request(.accessibility)
        }
        SnipPermissionGuide.bind(permissions: chain)
        // 启动只静默读取：不弹系统框、不请求授权（弹框留给用户点「授权」那一刻）
        chain.bootstrap()
    }

    /// 唤出剪贴板面板 —— 两个入口（状态栏菜单、全局热键）共用这一处
    ///
    /// 先重读权限再展示：面板页脚的辅助功能入口与设置页读同一份快照，
    /// 用户刚在系统设置勾完，这一次打开就该是绿的（不用重启应用）。
    func toggleClipboardPanel() {
        permissionChain?.refresh()
        clipboardPanel.toggle()
    }
}
