import AppKit
import NetworkMonitorCore

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?
    private var menuBarManager: MenuBarManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppContext.shared.configure(logger: OSLogLogger(category: "App"))
        // 启动自愈：包名改成「一览.app」后旧的 SMAppService 登记仍指向旧包路径（偏好是开、
        // 系统侧却没登记）。偏好为开时重新登记一次；失败则回滚偏好，设置页不会显示虚假的「已开启」。
        LaunchAtStartupService().reconcileAtLaunch()
#if DEBUG
        // 仅 DEBUG：实机取证可强制浅色/深色外观
        MenuPanelEvidence.applyAppearanceOverrideIfRequested()
#endif
        let coordinator = AppCoordinator()
        self.coordinator = coordinator
        menuBarManager = coordinator.start()
        // 系统菜单栏入口（右键菜单之外的另一处设置入口）
        if let menuBarManager {
            let mainMenu = NSMenu()
            let appItem = NSMenuItem()
            mainMenu.addItem(appItem)
            let appMenu = NSMenu()
            let settingsItem = NSMenuItem(title: "设置…", action: #selector(MenuBarManager.openSettingsFromMenu), keyEquivalent: ",")
            settingsItem.keyEquivalentModifierMask = [.command]
            settingsItem.target = menuBarManager
            appMenu.addItem(settingsItem)
            appMenu.addItem(.separator())
            appMenu.addItem(NSMenuItem(title: "退出 \(AppIdentity.displayName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
            appItem.submenu = appMenu
            NSApp.mainMenu = mainMenu
        }
        // 启动后预热一次面板：NSPopover 的窗口 / 约束引擎 / 首帧绘制都在首次 show 时才建，
        // 提前付掉这份一次性开销，首次点击不必再等 1 秒
        menuBarManager?.schedulePrewarm()
#if DEBUG
        // 仅 DEBUG：设置 NM_SNAPSHOT_DIR 时渲染面板快照并退出（见 MenuPanelSnapshot）
        MenuPanelSnapshot.runIfRequested(repository: coordinator.snapshotClipboardRepository,
                                          harness: coordinator.snapshotHarnessService,
                                          settings: coordinator.settingsWindow)
        // 仅 DEBUG：NM_THEME_HOT_PROBE=<目录> 时验证「切主题 → 设置窗口重绘」链路并退出
        SettingsThemeHotProbe.runIfRequested(settings: coordinator.settingsWindow)
        // 仅 DEBUG：NM_APPEARANCE_EVIDENCE=1 时打印三档 / 三主题的运行时结构并退出
        // （毛玻璃离屏不可辨，材质与档位的验收主判据是结构自证）
        if let manager = menuBarManager {
            AppearanceEvidence.runIfRequested(manager: manager)
        }
        // 仅 DEBUG：NM_NOTIFY_SELFCHECK=<file> 时跑一遍通知与音效自检并退出（取证用）
        NotificationSelfCheck.runIfRequested(coordinator: coordinator)
        // 仅 DEBUG：--measure-panel-open 时逐阶段计时并退出（性能回归取证）
        PanelOpenMeasure.runIfRequested(manager: menuBarManager)
        // 仅 DEBUG：NM_SHOW_PANEL=1 时走真实路径展开 popover 并保持打开（实机截图取证）
        MenuPanelEvidence.openIfRequested(manager: menuBarManager)
        // 仅 DEBUG：面板开着时抓一张屏，验证「对着面板截图抓到的是面板而非背景」
        if SnipPanelCaptureProbe.isRequested {
            SnipPanelCaptureProbe.run(capture: coordinator.snipController.captureService,
                                      manager: menuBarManager)
        }
#endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.stop()
        AppContext.shared.logger.info("应用退出")
    }
}