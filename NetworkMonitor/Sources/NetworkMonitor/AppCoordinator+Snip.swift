import AppKit
import NetworkMonitorCore

// MARK: - 截图与贴图装配（从组合根拆出，守住单文件门禁）

extension AppCoordinator {

    func setupSnip() {
        // 4b. 截图 / 贴图链路（热键注册 → 覆盖层选区 → 复制 / 贴到屏幕）
        snipController = SnipController(logger: logger)
        snipSettings = SnipSettingsWindow(logger: logger) { [weak self] in
            self?.snipController.hotKeySummary ?? "热键尚未注册"
        }
        snipController.onOpenSettings = { [weak self] in self?.snipSettings.show() }
        snipController.start()
    }
}
