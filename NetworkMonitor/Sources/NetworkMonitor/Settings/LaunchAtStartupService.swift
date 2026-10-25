import Foundation
import ServiceManagement
import NetworkMonitorCore

// MARK: - 开机自启动

/// 开机自启动开关 — 菜单与设置页共用一份实现
///
/// 真实状态以 `SMAppService` 注册结果为准，偏好键只做「用户意图」的本地记录：
/// 注册失败（未签名 / 系统拒绝）时要把键回滚，否则界面会显示已开启但实际没启动。
final class LaunchAtStartupService {

    private let storage: any KeyValueStorage
    private let logger: LoggingService

    init(storage: any KeyValueStorage = AppContext.shared.storage,
         logger: LoggingService = AppContext.shared.logger) {
        self.storage = storage
        self.logger = logger
    }

    /// 当前是否已登记开机自启动
    var isEnabled: Bool {
        storage.bool(forKey: ClipboardPreferences.launchAtStartupKey)
    }

    /// 切换登记状态
    ///
    /// - Parameter enabled: 目标状态
    /// - Returns: 是否成功（失败时已回滚偏好键）
    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool {
        storage.set(enabled, forKey: ClipboardPreferences.launchAtStartupKey)
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            logger.error("开机自启动切换失败：\(error.localizedDescription)")
            storage.set(!enabled, forKey: ClipboardPreferences.launchAtStartupKey)
            return false
        }
    }
}
