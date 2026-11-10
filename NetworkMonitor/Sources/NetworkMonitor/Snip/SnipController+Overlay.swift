import AppKit
import NetworkMonitorCore

// MARK: - 覆盖层生命周期与前台协调（从编排主类拆出，守住单文件门禁）

extension SnipController {

    /// 生成并上屏覆盖层；返回是否拿到键盘焦点
    func presentOverlays(_ result: [SnipCapturedImage]) {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let windowInfos = captureService.windowInfos()
        let previous = lastSelection
        let history = selectionHistory
        overlays = result.map { captured in
            SnipOverlayWindow(display: captured.display,
                              screenshot: captured.image,
                              windowInfos: windowInfos,
                              lastSelection: previous,
                              history: history,
                              primaryHeight: primaryHeight,
                              delegate: self)
        }
        // 先装键盘兜底再上屏：上屏瞬间按下的键（双击热键、抢手速按 Esc）也要能被接住
        installKeyboardFallback()
        // 只有第一屏抢 App 激活并成为 key window；其余屏只需挂到屏幕上，
        // 逐屏都 activate 会让焦点在窗口间来回跳（多屏时按键会丢）
        var keyAssigned = false
        for window in overlays {
            if keyAssigned {
                window.orderFront(nil)
            } else {
                keyAssigned = window.present()
            }
        }
        guard keyAssigned else {
            // 窗口挂上了但没拿到键盘：明确告诉用户，而不是让人对着不响应的覆盖层按半天
            logger.warning("截图覆盖层未能成为键盘焦点（App 可能未激活）")
            SnipFailureNotice.present(message: "覆盖层未接管键盘，请用鼠标选区或再按一次快捷键", logger: logger)
            return
        }
        logger.info("截图覆盖层已就绪，共 \(overlays.count) 屏")
        #if DEBUG
        if SnipVisibleProbe.isRequested {
            SnipVisibleProbe.capture(logger: logger)
        }
        #endif
    }

    /// 收掉全部覆盖层并恢复菜单栏激活策略
    func dismissOverlays() {
        for window in overlays {
            window.orderOut(nil)
            window.close()
        }
        overlays.removeAll()
        captures.removeAll()
        removeKeyboardFallback()
        restoreMenuBarPolicy()
    }

    /// 截图开始前就把前台拿到手，并等到真的拿到（详见 beginSnip 里的说明）
    ///
    /// 关键点：在抓屏之前就完成「切策略 → 激活 → 确认 frontmost 是自己」。
    /// 抓屏本身要几百毫秒，这段时间前台已经稳稳落在本 App，
    /// 覆盖层一上屏按键就直接派给视图，不必再依赖上屏后的异步激活（那是竞态来源）。
    func claimForegroundForCapture() async {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
        let deadline = Date().addingTimeInterval(0.6)
        let selfPID = ProcessInfo.processInfo.processIdentifier
        while Date() < deadline {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == selfPID { return }
            NSApp.activate(ignoringOtherApps: true)
            try? await Task.sleep(nanoseconds: 30_000_000)
        }
        logger.warning("截图前未能在 0.6 秒内取得前台，首下按键可能需按第二次")
    }

    /// 等到本 App 真的成为系统前台（最多 1.2 秒，超时也继续，不阻塞截图）
    ///
    /// 菜单栏 App 从「不是可激活应用」切到前台，系统要先做一次策略迁移，
    /// 首轮往往要几百毫秒；这段延迟正好覆盖「按热键后立刻按 Esc」的时机，
    /// 于是第一下按键会投给原前台 App 而丢失。等待期间反复重试激活，
    /// 拿到前台才上屏。超时仍然上屏（宁可第一下按键不灵，也不能卡住截图）。
    func waitForForeground() async {
        let deadline = Date().addingTimeInterval(1.2)
        let selfPID = ProcessInfo.processInfo.processIdentifier
        while Date() < deadline {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == selfPID { return }
            NSApp.activate(ignoringOtherApps: true)
            try? await Task.sleep(nanoseconds: 40_000_000)
        }
        logger.warning("截图前未能在 1.2 秒内取得前台，按键可能需按第二次才生效")
    }

    /// 退出截图态：把激活策略切回 .accessory（菜单栏 App 不该长期占着前台与 Dock 图标）
    func restoreMenuBarPolicy() {
        guard NSApp.activationPolicy() == .regular else { return }
        NSApp.setActivationPolicy(.accessory)
    }
}
