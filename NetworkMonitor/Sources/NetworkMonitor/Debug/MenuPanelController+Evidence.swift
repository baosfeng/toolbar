import AppKit

// MARK: - 面板取证与测量钩子（仅 DEBUG）

/// 真实窗口渲染路径上的取证钩子 —— 从 `MenuPanelController+Open.swift` 拆出
///
/// 这些方法只给 Debug/ 下的快照与测量链路用（nmcli 验收 / 证据截图），不进生产路径；
/// 与开合逻辑放一起只会让「打开面板」这个文件多背一段无关代码。
#if DEBUG

extension MenuPanelController {

    /// 取证专用（仅 DEBUG）：强制 popover 内容与窗口外观（真实窗口渲染，非离屏缓存）
    func forceAppearanceForEvidence(_ name: NSAppearance.Name) {
        guard let appearance = NSAppearance(named: name) else { return }
        NSApp.appearance = appearance
        content.appearance = appearance
        popover.contentViewController?.view.appearance = appearance
        popover.contentViewController?.view.window?.appearance = appearance
    }

    /// 取证专用（仅 DEBUG）：切换展示分页
    func selectTabForEvidence(_ tab: MenuPanelTab) {
        content.select(tab: tab)
        updateContentSize(force: true)
    }

    /// 取证专用（仅 DEBUG）：popover 真实窗口号与 frame（供 screencapture -l 用）
    func evidenceWindow() -> (number: Int, frame: NSRect)? {
        guard popover.isShown, let window = popover.contentViewController?.view.window else { return nil }
        return (window.windowNumber, window.frame)
    }

    /// 测量专用（仅 DEBUG）：popover 内容窗口对象（强制首帧落屏用）
    func measurePanelWindow() -> NSWindow? { popover.contentViewController?.view.window }

    /// 取证专用（仅 DEBUG）：当前分页
    var currentTabForEvidence: MenuPanelTab { content.currentTab }

    /// 取证专用（仅 DEBUG）：分段条当前可见分页（隐藏分页后应少一段）
    var visibleTabsForEvidence: [MenuPanelTab] { content.tabBar.visibleTabs }

    /// 取证专用（仅 DEBUG）：系统页二级详情是否展开（未装配视为未展开）
    var systemDetailShownForEvidence: Bool { content.systemPaneIfLoaded?.isShowingDetail ?? false }

    /// 取证专用（仅 DEBUG）：进入系统页二级详情（CPU），用于验证隐藏分页时详情收起
    func showSystemDetailForEvidence() {
        content.select(tab: .system)
        // 取证路径显式装配：这里不依赖 select 的副作用，读 pane 前先把系统页建出来
        content.ensurePaneLoaded(.system)
        content.systemPane.showDetail(.cpu)
        updateContentSize(force: true)
    }
}

#endif
