import AppKit
import NetworkMonitorCore
import NetworkMonitorFeatureSnip
import NetworkMonitorUI

// MARK: - 截图与贴图装配（从组合根拆出，守住单文件门禁）

extension AppCoordinator {

    func setupSnip() {
        // 4b. 截图 / 贴图链路（热键注册 → 覆盖层选区 → 复制 / 贴到屏幕）
        snipController = SnipController(logger: logger)
        // 截图页的「控制」信息来自 SnipController 的热键摘要；设置入口统一走设置窗口
        snipController.onOpenSettings = { [weak self] in
            self?.settingsWindow?.show(section: .capture)
        }
        // 截图完成提示音：走统一事件表（截图完成一行），默认关
        snipController.onCaptureCompleted = { [weak self] in
            self?.soundFeedback.play(.snipCapture)
        }
        snipController.start()
        // 启动预热已下线：它原来做的是「切 .regular → 激活 → 1.2 秒后切回 .accessory」，
        // 目的是把「菜单栏 App 变成可激活应用」的那次策略迁移提前付掉，避免首次截图丢键。
        // 代价是启动 1.5 秒后 Dock 里凭空出现本应用图标 1.2 秒——用户很可能看到的就是这一下
        // （口径：「每次我们截图的时候，都会出现我们的软件出现在 dock 栏」）。
        // 现在截图全程不切激活策略（见 SnipForegroundPolicy），没有迁移要付，
        // 首次按键由覆盖层的有限重试 + CGEventTap 兜底接住，预热自然不再需要。
    }
}

extension AppCoordinator: SnipSettingsDelegate {
    func settingsDidChangeSnipHotKey(_ action: SnipHotKeyAction, combo: HotKeyCombo) -> Bool {
        snipController?.updateHotKey(for: action, combo: combo) ?? false
    }
}
