import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?
    private var menuBarManager: MenuBarManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppContext.shared.configure(logger: OSLogLogger(category: "App"))
        // 偏好域迁移必须在**任何读偏好的服务之前**：改了 bundle id 就等于换了偏好域，
        // 晚于首读会被「当前域已有键」判成跳过，用户设置表现为全部回到默认。
        PreferenceDomainMigrator.runIfNeeded(currentBundleIdentifier: Bundle.main.bundleIdentifier)
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
        // 仅 DEBUG：设置 NM_DRAWN_PROBE 时渲染自绘组件样例并退出（见 DrawnUIProbe）
        DrawnUIProbe.runIfRequested()
        // 仅 DEBUG：设置 NM_SNAPSHOT_DIR 时渲染面板快照并退出（见 MenuPanelSnapshot）
        MenuPanelSnapshot.runIfRequested(repository: coordinator.snapshotClipboardRepository,
                                          harness: coordinator.snapshotHarnessService,
                                          settings: coordinator.settingsWindow)
        // 仅 DEBUG：NM_PERMISSION_STATE_SNAPSHOT=1 时导出权限页的「检测中 / 需重启」取证图
        if let directory = SettingsPermissionStateSnapshot.requestedDirectory {
            SettingsPermissionStateSnapshot.runIfRequested(directory: directory)
        }
        // 仅 DEBUG：NM_UPDATE_PROBE=live|failure 时跑一次更新检查并打印状态 / 界面文案
        UpdateCheckProbe.runIfRequested(coordinator: coordinator)
        // 仅 DEBUG：NM_THEME_HOT_PROBE=<目录> 时验证「切主题 → 设置窗口重绘」链路并退出
        SettingsThemeHotProbe.runIfRequested(settings: coordinator.settingsWindow)
        // 仅 DEBUG：NM_APPEARANCE_EVIDENCE=1 时打印三档 / 三主题的运行时结构并退出
        // （毛玻璃离屏不可辨，材质与档位的验收主判据是结构自证）
        if let manager = menuBarManager {
            AppearanceEvidence.runIfRequested(manager: manager)
        }
        // 仅 DEBUG：NM_PIN_DRAG_PROBE=1|hold 时跑贴图窗鼠标手势矩阵并退出（拖动取证用）
        PinDragProbe.runIfRequested(pin: coordinator.snipController.pinWindows)
        // 仅 DEBUG：NM_PIN_MENU_PROBE=1 时按四份偏好装配菜单并打印，验证跨组换序生效
        PinMenuProbe.run(storage: SnapshotKeyValueStorage())
        // 仅 DEBUG：NM_PIN_BOARD_PROBE=<目录> 时出「棋盘底 + 灰度 / 反色」四联取证图并退出
        PinBoardProbe.runIfRequested()
        // 仅 DEBUG：NM_NOTIFY_SELFCHECK=<file> 时跑一遍通知与音效自检并退出（取证用）
        NotificationSelfCheck.runIfRequested(coordinator: coordinator)
        // 仅 DEBUG：--measure-panel-open 时逐阶段计时并退出（性能回归取证）
        PanelOpenMeasure.runIfRequested(manager: menuBarManager)
        // 仅 DEBUG：NM_CLIPBOARD_PREVIEW_PROBE=<目录> 时真开剪贴板面板 + 空格预览并抓屏取���
        if ClipboardPreviewProbe.runIfRequested(coordinator: coordinator) { return }
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
        // 预览的临时 .txt 目录随进程退出一并清掉（幂等；失败只记日志，不阻断退出）
        ClipboardPreviewBuilder.removeTemporaryDirectory(ClipboardPreviewBuilder.defaultTemporaryDirectory())
        coordinator?.stop()
        AppContext.shared.logger.info("应用退出")
    }
}