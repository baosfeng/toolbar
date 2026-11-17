import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 采集暂停 / 恢复

/// 暂停与恢复 — 从 `PasteboardWatcher` 拆出的状态机扩展
///
/// 拆出原因：`PasteboardWatcher` 族已顶到同族门禁基线（只允许变小），暂停能力是新领域，
/// 独立成文件才能在不撑大原族的前提下加分支；原文件只保留两处闸门（start / capture）。
///
/// 语义：暂停 = 停轮询 + 偏好置位；恢复 = 偏好复位 + 按当前采集模式重启。
/// **幂等**：重复暂停 / 重复恢复不重复停轮询、不重复注册观察者、不重复打日志。
extension PasteboardWatcher {   // 暂停 / 恢复状态机

    /// 用户是否已主动暂停采集（唯一真源是偏好，采集器不另存一份状态）
    var isPaused: Bool { preferences.isPaused }

    /// 暂停采集（幂等）
    func pause() {
        guard ClipboardPauseLogic.shouldTransition(currentlyPaused: isPaused, target: true) else { return }
        preferences.isPaused = true
        // 停轮询走既有 stop()：顺带摘掉变更唤醒观察者与活跃度探针，不留后台定时器
        stop()
        onStateChange?(.paused)
        logger.info("剪贴板采集已暂停（复制的内容不再入库）")
    }

    /// 恢复采集（幂等）
    func resume() {
        guard ClipboardPauseLogic.shouldTransition(currentlyPaused: isPaused, target: false) else { return }
        preferences.isPaused = false
        // start() 内部按采集模式分支：轮询模式重启轮询，按需模式只发大状态不建 Timer
        start()
        logger.info("剪贴板采集已恢复")
    }

    /// 暂停 / 恢复切换，返回切换后的暂停态
    @discardableResult
    func togglePause() -> Bool {
        if isPaused { resume() } else { pause() }
        return isPaused
    }
}

// MARK: - 面板接线

/// 面板侧接线 — 键位 / 提示行点击 / 打开面板时的状态同步，都收敛到这一处
extension ClipboardPanelController {   // 面板暂停入口

    /// ⌘P 与提示行点击：切换后立即把新状态写到提示行
    func togglePause() {
        let paused = captureService.togglePause()
        content.revealPauseState(paused)
        logger.info("剪贴板暂停切换：isPaused=\(paused)")
    }

    /// 面板每次打开时对齐暂停态（另一个入口可能是菜单栏或设置页）
    func syncPauseState() {
        content.onRequestTogglePause = { [weak self] in self?.togglePause() }
        content.revealPauseState(captureService.isPaused)
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