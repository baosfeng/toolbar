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
            // App 菜单项：title 留空时 AppKit 会用进程名填充（显示为「一览」），这里显式给上
            let appItem = NSMenuItem(title: AppIdentity.displayName, action: nil, keyEquivalent: "")
            mainMenu.addItem(appItem)
            let appMenu = NSMenu()
            let settingsItem = NSMenuItem(title: "设置…", action: #selector(MenuBarManager.openSettingsFromMenu), keyEquivalent: ",")
            settingsItem.keyEquivalentModifierMask = [.command]
            settingsItem.target = menuBarManager
            appMenu.addItem(settingsItem)
            appMenu.addItem(.separator())
            appMenu.addItem(NSMenuItem(title: "退出 \(AppIdentity.displayName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
            appItem.submenu = appMenu
            // 编辑菜单：文本框里的 ⌘A / ⌘C / ⌘V / ⌘X / ⌘Z **只能**靠菜单项触发
            //
            // AppKit 的 field editor 不处理这些组合键，标准路径是 NSApplication 沿 mainMenu
            // 找带对应 keyEquivalent 的项再走响应链。此前只在 mainMenu 里放了一个 App 菜单，
            // 于是截图文字框、剪贴板搜索框里 ⌘C / ⌘V 全部无效（用户报的「全选、复制、粘贴都不行」）。
            // 这些项的 target 留空 = 走 first responder 响应链，天然对任意输入框生效。
            mainMenu.addItem(Self.makeEditMenuItem())
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
        // 仅 DEBUG：NM_UPDATE_PROBE=states 时把关于页打进四段安装态并逐态截图
        UpdateInstallStateProbe.runIfRequested(coordinator: coordinator)
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
        // 仅 DEBUG：NM_PANEL_PIN_PROBE=1 时在同一次展开里逐页切过去，核对右上角是否恒定
        if PanelPinProbe.isRequested, let manager = menuBarManager {
            PanelPinProbe.run(manager: manager)
        }
        // 仅 DEBUG：NM_PANEL_PIN_TRACE=1 时逐帧记录展开过程与切页后的窗口 frame（定位过程性抖动）
        if PanelPinTraceProbe.isRequested, let manager = menuBarManager {
            PanelPinTraceProbe.run(manager: manager)
        }
        // 仅 DEBUG：面板开着时抓一张屏，验证「对着面板截图抓到的是面板而非背景」
        if SnipPanelCaptureProbe.isRequested {
            SnipPanelCaptureProbe.run(capture: coordinator.snipController.captureService,
                                      manager: menuBarManager)
        }
#endif
    }

    /// 标准编辑菜单 —— 让所有文本输入框拿到 ⌘A / ⌘C / ⌘V / ⌘X / ⌘Z / ⌘⇧Z
    ///
    /// selector 全部是 NSResponder 的标准动作（selectAll: / copy: / paste: / cut: / undo: / redo:），
    /// searchField、NSTextField、NSTextView 都实现了它们，因此这里不挂 target，
    /// 让响应链自己找人处理。
    private static func makeEditMenuItem() -> NSMenuItem {
        // 必须给 title：无 title 的 NSMenuItem 在菜单栏里不占位（实测只有 App 菜单一项），
        // 而第一个无 title 项会被 AppKit 顶成「应用名」，所以不能靠「留空自动命名」。
        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "编辑")
        // 顺序与系统标准一致：撤销 / 重做 / 剪切 / 复制 / 粘贴 / 全选
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        return editItem
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 预览的临时 .txt 目录随进程退出一并清掉（幂等；失败只记日志，不阻断退出）
        ClipboardPreviewBuilder.removeTemporaryDirectory(ClipboardPreviewBuilder.defaultTemporaryDirectory())
        coordinator?.stop()
        AppContext.shared.logger.info("应用退出")
    }
}