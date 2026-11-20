import AppKit
import NetworkMonitorCore

// MARK: - 菜单面板（显示 / 收起 / 预热）

/// 面板生命周期 — 展开 / 收起 / 预热，打开路径要逐阶段打点（见 PanelOpenProbe）
///
/// 刷新链路的动作在 `MenuPanelController+Refresh.swift`，「要不要刷新」的判定在
/// NetworkMonitorUI 的 `PanelRefreshPolicy` / `PanelContentSizing`；本文件只管开合本身。
extension MenuPanelController {

    // MARK: - 显示 / 收起

    /// 状态栏按钮点击入口：已展开则收起，否则在按钮下方展开
    func toggle(relativeTo rect: NSRect, of view: NSView) {
        if popover.isShown {
            close()
            return
        }
        // transient 行为下，点击状态栏按钮会先自动收起再触发按钮动作：
        // 极短时间内的再次 toggle 视为「本次关闭」的续动作，不再重新展开。
        guard Date().timeIntervalSince(lastCloseDate) > 0.25 else { return }
        show(relativeTo: rect, of: view)
    }

    /// 展开面板并强制全量刷新
    func show(relativeTo rect: NSRect, of view: NSView) {
        // 【时序敏感】必须在 popover 成为 key window 之前同步记录目标 App，
        // 否则 frontmost 会变成本 App，合成的 ⌘V 永远落回自己（见 ClipboardPaster 注释）。
        PanelOpenProbe.mark("01 recordTargetApplication")
        paster.recordTargetApplication()
        PanelOpenProbe.mark("02 refreshAll")
        refreshAll()
        PanelOpenProbe.mark("03 popover.show")
        popover.show(relativeTo: rect, of: view, preferredEdge: .minY)
        PanelOpenProbe.mark("04 updateContentSize(force)")
        updateContentSize(force: true)
        PanelOpenProbe.mark("05 makeFirstResponder")
        if let window = popover.contentViewController?.view.window {
            window.makeFirstResponder(content)
        }
        PanelOpenProbe.mark("06 show 返回")
    }

    // MARK: - 预热

    /// 启动后预热一次：把 NSPopover 的窗口、约束引擎与首帧绘制提前建好
    ///
    /// NSPopover 的窗口在**第一次 show 时**才创建，实测「窗口 + 整棵约束引擎 + 首帧绘制」
    /// 占首次打开约 375ms（再次打开只需 60ms 左右）；启动后先在真实路径上开一次再立刻收起，
    /// 把这份一次性开销挪到用户点击之前。
    ///
    /// 不可见性：全程在同一个 runloop 轮次内完成（show → 窗口 alpha 归零 → 收起），
    /// 窗口在任何一次提交前就已透明，用户看不到弹出。
    func prewarmPanelIfNeeded(relativeTo rect: NSRect, of view: NSView) {
        guard !hasPrewarmed, !popover.isShown else { return }
        hasPrewarmed = true
        let savedAnimates = popover.animates
        popover.animates = false
        defer { popover.animates = savedAnimates }
        // 数据先就位（首屏内容 + 内容树布局），再开窗
        refreshAll()
        popover.show(relativeTo: rect, of: view, preferredEdge: .minY)
        let window = popover.contentViewController?.view.window
        window?.alphaValue = 0
        popover.performClose(nil)
        window?.alphaValue = 1
        logger.info("面板预热完成（首次打开的窗口与布局开销已提前付掉）")
    }

    /// 收起面板
    func close() {
        guard popover.isShown else { return }
        popover.performClose(nil)
    }

    /// 是否已展开
    var isShown: Bool { popover.isShown }

    // MARK: - NSPopoverDelegate

    func popoverDidClose(_ notification: Notification) {
        lastCloseDate = Date()
        // 收起后清空键盘焦点，下次展开从第一行开始
        content.resetKeyboardFocus()
    }
}
