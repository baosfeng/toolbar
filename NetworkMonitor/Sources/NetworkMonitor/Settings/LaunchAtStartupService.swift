import Foundation
import ServiceManagement
import NetworkMonitorCore

// MARK: - 开机自启动

/// 开机自启动开关 — 菜单与设置页共用一份实现
///
/// 真实状态以 `SMAppService` 注册结果为准，偏好键只做「用户意图」的本地记录：
/// 注册失败（未签名 / 系统拒绝）时要把键回滚，否则界面会显示已开启但实际没启动。
/// 判定与回滚都在 Core 的 `LaunchAtStartupReconciler`（可单测），这里只做 SMAppService 接线。
final class LaunchAtStartupService {

    private let reconciler: LaunchAtStartupReconciler

    init(storage: any KeyValueStorage = AppContext.shared.storage,
         logger: LoggingService = AppContext.shared.logger,
         registrar: any LaunchAtStartupRegistering = SMAppServiceLoginItem()) {
        self.reconciler = LaunchAtStartupReconciler(storage: storage,
                                                    key: ClipboardPreferences.launchAtStartupKey,
                                                    registrar: registrar,
                                                    logger: logger)
    }

    /// 当前是否已登记开机自启动（偏好记录的用户意图，不代表系统侧真的已登记）
    var isEnabled: Bool {
        reconciler.isEnabled
    }

    /// 切换登记状态
    ///
    /// - Parameter enabled: 目标状态
    /// - Returns: 是否成功（失败时已回滚偏好键）
    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool {
        reconciler.setEnabled(enabled)
    }

    /// 启动自愈：包名改成「一览.app」后，旧的登录项登记指向旧包路径（系统侧状态失效），
    /// 偏好为开但系统侧没登记时重新登记；登记失败则把偏好回滚为关并记 error 日志
    @discardableResult
    func reconcileAtLaunch() -> LaunchAtStartupReconcileOutcome {
        reconciler.reconcileAtLaunch()
    }
}

// MARK: - SMAppService 接线

/// 把 `SMAppService.mainApp.status` 翻译成 Core 的四档语义
final class SMAppServiceLoginItem: LaunchAtStartupRegistering {

    var registration: LaunchAtStartupRegistration {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered: return .notRegistered
        case .notFound: return .notFound
        @unknown default: return .notRegistered
        }
    }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }
}
