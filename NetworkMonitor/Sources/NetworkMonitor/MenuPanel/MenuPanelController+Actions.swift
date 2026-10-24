import AppKit
import NetworkMonitorCore
import ServiceManagement

// MARK: - 菜单面板动作（MenuPanelController 扩展）

/// 面板动作与视图委托 — 粘贴、剪贴板入口、开机自启动切换，以及 `MenuPanelViewDelegate` 实现。
///
/// 拆出原因：`MenuPanelController` 主体超过单文件 15 KiB 上限，按「主类 + 动作扩展」范式分离。
/// 由主文件 `wireActions()` 调用的动作方法声明为 internal（原 private），
/// 供同模块的 `MenuPanelController.swift` 跨文件装配；同目录内无其他调用方。
extension MenuPanelController: MenuPanelViewDelegate {

    // MARK: - 动作
    //
    // 以下成员（`paste` / `requestClipboardSettings` / `requestClipboardHistory` /
    // `toggleLaunchAtStartup` / `isLaunchAtStartupSaved`）由主文件 `wireActions()` 装配
    // 与中频刷新读取，故由 private 放宽为 internal。

    /// 点击条目：收起面板后走与剪贴板面板一致的粘贴路径
    func paste(_ item: ClipboardItem) {
        close()
        // 面板展开时本 App 会被激活；收起后先把目标 App 拉回前台，
        // 否则合成的 ⌘V 会落回自己（只写剪贴板却不粘贴）。
        if let bundleID = paster.targetBundleID,
           let target = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            target.activate(options: [])
        }
        paster.paste(item, asPlainText: false) { [weak self] outcome in
            let message = outcome.message
            guard let self, !message.isEmpty else { return }
            self.logger.info("菜单面板粘贴：\(message)")
        }
    }

    func requestClipboardSettings() {
        close()
        onOpenClipboardSettings?()
    }

    func requestClipboardHistory() {
        close()
        onOpenClipboardHistory?()
    }

    var isLaunchAtStartupSaved: Bool {
        storage.bool(forKey: ClipboardPreferences.launchAtStartupKey)
    }

    /// 开机自启动切换（SMAppService 注册 / 注销，失败时在剪贴板页给提示）
    func toggleLaunchAtStartup() {
        let wasEnabled = isLaunchAtStartupSaved
        let target = !wasEnabled
        storage.set(target, forKey: ClipboardPreferences.launchAtStartupKey)

        do {
            if target {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            content.launchAtStartupEnabled = target
            updateContentSize()
        } catch {
            // 回滚偏好，避免界面状态与系统真实注册状态不一致
            storage.set(wasEnabled, forKey: ClipboardPreferences.launchAtStartupKey)
            content.launchAtStartupEnabled = wasEnabled
            logger.error("开机自启动切换失败: \(error)")
        }
    }

    // MARK: - MenuPanelViewDelegate

    func menuPanelViewDidChangeContent(_ view: MenuPanelView) {
        updateContentSize()
        // 切到额度页时才触发刷新（monitor 内部 60 秒节流）
        if view.currentTab == .credits {
            billingMonitor?.refresh()
        }
    }

    func menuPanelViewDidSelectTab(_ view: MenuPanelView) {
        // 切到 Token 页时按需增量刷新（服务内部串行、不重入；数据未变则快速返回）
        if view.currentTab == .token {
            harnessUsage?.refreshIfNeeded()
        }
    }

    func menuPanelViewDidRequestClose(_ view: MenuPanelView) {
        close()
    }

    func menuPanelViewDidRequestQuit(_ view: MenuPanelView) {
        NSApplication.shared.terminate(nil)
    }

    func menuPanelViewDidRequestClipboardSettings(_ view: MenuPanelView) {
        requestClipboardSettings()
    }

    func menuPanelViewDidRequestToggleLaunchAtStartup(_ view: MenuPanelView) {
        toggleLaunchAtStartup()
    }

    func menuPanelViewDidRequestTransferSettings(_ view: MenuPanelView) {
        transferController?.showSettings()
    }
}