import AppKit
import NetworkMonitorCore

// MARK: - 状态栏右键菜单

/// 状态栏右键菜单 — 设置 / 暂停采集 / 退出
///
/// 拆出原因：`MenuBarManager` 族已顶到同族门禁基线（只允许变小），菜单构造是新入口，
/// 独立成文件；菜单标题每次弹出时现算，暂停态的文案永远跟采集服务一致。
enum MenuBarPauseMenu {

    /// 每次弹出都重建菜单：暂停 / 恢复的标题与当前状态强相关，缓存会出现「点了暂停仍显示暂停采集」
    @MainActor
    static func make(target: MenuBarManager) -> NSMenu {
        let menu = NSMenu()
        // 剪贴板历史是独立浮层，菜单面板里没有分页入口：这里必须留一项，
        // 否则用户只剩全局快捷键 ⌥⌘V 一条路（齿轮菜单已收口到本菜单）
        let historyItem = NSMenuItem(title: "剪贴板历史…",
                                     action: #selector(MenuBarManager.openClipboardHistoryFromMenu),
                                     keyEquivalent: "v")
        historyItem.keyEquivalentModifierMask = [.command, .option]
        historyItem.target = target
        menu.addItem(historyItem)
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "设置…", action: #selector(MenuBarManager.openSettingsFromMenu), keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = [.command, .option]
        settingsItem.target = target
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        let isPaused = target.clipboardCapture?.isPaused ?? false
        let pauseItem = NSMenuItem(title: ClipboardPauseLogic.menuTitle(isPaused: isPaused),
                                   action: #selector(MenuBarManager.toggleClipboardPause),
                                   keyEquivalent: "")
        pauseItem.target = target
        menu.addItem(pauseItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 \(AppIdentity.displayName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = [.command]
        menu.addItem(quitItem)
        return menu
    }
}
