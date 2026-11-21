import AppKit
import NetworkMonitorCore
import NetworkMonitorFeatureClipboard

// MARK: - 面板接线

/// 面板侧接线 — 键位 / 提示行点击 / 打开面板时的状态同步，都收敛到这一处
extension ClipboardPanelController {   // 面板暂停入口

    /// ⌘P 与提示行点击：切换后立即把新状态写到提示行
    func togglePause() {
        let paused = captureService.togglePause()
        content.revealPauseState(paused, until: preferences.pausedUntil)
        logger.info("剪贴板暂停切换：isPaused=\(paused)")
    }

    /// 面板每次打开时对齐暂停态（另一个入口可能是菜单栏或设置页）
    func syncPauseState() {
        content.onRequestTogglePause = { [weak self] in self?.togglePause() }
        content.revealPauseState(captureService.isPaused, until: preferences.pausedUntil)
    }

    /// 定时暂停到点自愈：挂在面板打开与面板刷新节拍上，不新建常驻 Timer
    func expireTimedPauseIfNeeded(now: Date = Date()) {
        guard captureService.resumeTimedPauseIfExpired(now: now) else { return }
        // 自动恢复要让用户看得见：提示行回到键位帮助，并给一次明确提示
        content.revealPauseState(false)
        content.showHint("定时暂停到点，已自动恢复采集")
        logger.info("剪贴板定时暂停到点，面板已切回可采集提示")
    }

    /// 暂停时点「采集当前剪贴板」给出可恢复提示（不静默失败）
    func captureNowUnlessPaused() {
        guard !captureService.isPaused else {
            content.showHint(ClipboardPauseLogic.captureBlockedHint)
            return
        }
        captureService.captureNow()
    }
}
