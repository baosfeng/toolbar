import Foundation
import NetworkMonitorCore

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
    ///
    /// 定时暂停到点即视为未暂停：面板 / 状态栏据此不再显示可恢复入口，与自动恢复同一口径。
    public var isPaused: Bool { preferences.isPausedNow }

    /// 偏好里是否留有暂停痕迹（开关置位或定时截止未清）——恢复的幂等判据
    var hasPauseRecord: Bool {
        preferences.isPaused || preferences.pausedUntil.timeIntervalSince1970 > 0
    }

    /// 暂停采集到手动恢复（幂等）
    public func pause() { pause(until: .distantPast) }

    /// 暂停采集到指定时刻（哨兵值 = 到手动恢复）
    ///
    /// 已暂停时再选新时长只重写截止时刻，不重复停轮询、不重复打日志。
    public func pause(until endDate: Date) {
        let wasPaused = hasPauseRecord
        // 先写截止时刻再置开关：isPausedNow 两者都读，反过来会先被判定成「已到点」
        preferences.pausedUntil = endDate
        preferences.isPaused = true
        guard ClipboardPauseLogic.shouldTransition(currentlyPaused: wasPaused, target: true) else { return }
        // 停轮询走既有 stop()：顺带摘掉变更唤醒观察者与活跃度探针，不留后台定时器
        stop()
        onStateChange?(.paused)
        logger.info("剪贴板采集已暂停（复制的内容不再入库）")
    }

    /// 恢复采集（幂等）
    public func resume() {
        guard hasPauseRecord else { return }
        preferences.isPaused = false
        // 截止时刻一并清掉：否则「定时暂停历史」会让下次恢复判据与引用都错位
        preferences.pausedUntil = .distantPast
        // start() 内部按采集模式分支：轮询模式重启轮询，按需模式只发大状态不建 Timer
        start()
        logger.info("剪贴板采集已恢复")
    }

    /// 定时暂停到点自动恢复 —— 由宿主既有刷新节拍调用（不新建常驻 Timer）
    @discardableResult
    public func resumeTimedPauseIfExpired(now: Date) -> Bool {
        guard hasPauseRecord, !ClipboardPauseLogic.isPausedNow(paused: preferences.isPaused,
                                                               pausedUntil: preferences.pausedUntil,
                                                               now: now) else { return false }
        resume()
        logger.info("剪贴板定时暂停到点，已自动恢复采集")
        return true
    }

    /// 暂停 / 恢复切换，返回切换后的暂停态
    @discardableResult
    public func togglePause() -> Bool {
        if isPaused { resume() } else { pause() }
        return isPaused
    }
}
