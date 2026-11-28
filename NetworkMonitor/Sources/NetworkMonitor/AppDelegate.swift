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