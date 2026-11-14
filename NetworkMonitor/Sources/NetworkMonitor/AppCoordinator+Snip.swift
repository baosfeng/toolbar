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
        // 截图完成提示音：走统一事件表（截图完成一行），默认关
        snipController.onCaptureCompleted = { [weak self] in
            self?.soundFeedback.play(.snipCapture)
        }
        snipController.start()
        // 启动预热：完整走一遍「切前台 → 退回菜单栏态」
        //
        // LSUIElement 的菜单栏 App 从「不可激活」切到前台时，系统要做一次策略迁移，
        // 这时段的键盘事件会丢——实测第一次截图按 Esc 必定无效，第二次起才正常。
        // 启动阶段先把这次迁移付掉（切 .regular → 激活 → 等迁移完成 → 切回 .accessory），
        // 正式截图时的切换就是「第二次」，不再有过渡期丢键。
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            NSApp.setActivationPolicy(.accessory)
            logger.info("菜单栏激活预热完成")
        }
    }
}

extension AppCoordinator: SnipSettingsDelegate {
    func settingsDidChangeSnipHotKey(_ action: SnipHotKeyAction, combo: HotKeyCombo) -> Bool {
        snipController?.updateHotKey(for: action, combo: combo) ?? false
    }
}
