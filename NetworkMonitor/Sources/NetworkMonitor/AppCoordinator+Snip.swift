import AppKit
import NetworkMonitorCore

// MARK: - 截图与贴图装配（从组合根拆出，守住单文件门禁）

extension AppCoordinator {

    func setupSnip() {
        // 4b. 截图 / 贴图链路（热键注册 → 覆盖层选区 → 复制 / 贴到屏幕）
        snipController = SnipController(logger: logger)
        // 截图页的「控制」信息来自 SnipController 的热键摘要；设置入口统一走设置窗口
        snipController.onOpenSettings = { [weak self] in
            self?.settingsWindow?.show(section: .capture)
        }
        snipController.start()
    }
}
