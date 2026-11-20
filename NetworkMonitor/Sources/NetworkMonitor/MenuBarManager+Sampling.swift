import Foundation
import NetworkMonitorCore

// MARK: - 采样节拍（随面板可见性降频）

/// 状态栏 1 秒刷新链里的两路采样节流 —— 拆出来两个理由：面板收起时无人看（系统 1→5 秒、
/// nettop 3→15 秒）；MenuBarManager.swift 已到单文件字节上限。
/// 判定走 Core 的 `MinimumIntervalGate`：按本次生效的间隔构造闸门、以上次放行时刻续窗口，
/// 换间隔不会多放行一次；状态栏网速由 monitor.poll() 提供，不走这里，收起时照常每秒刷新。
extension MenuBarManager {

    /// 面板收起时的系统采样周期下限（秒）：保留告警阈值所需的灵敏度，又能去掉无人看的帧
    private static let hiddenSystemSampleInterval: TimeInterval = 5
    /// 面板展开时的进程采样周期（秒）：与 ProcessNetworkMonitor 内部节流对齐
    private static let visibleProcessPollInterval: TimeInterval = 3
    /// 面板收起时的进程采样周期（秒）：nettop 每次 fork 都有实打实的 CPU 成本
    private static let hiddenProcessPollInterval: TimeInterval = 15

    /// 按面板可见性与各自节流周期触发一次采样
    func pollSamplingIfNeeded(now: Date) {
        clipboardCapture?.resumeTimedPauseIfExpired(now: now)   // 定时暂停到点恢复（幂等，不另起 Timer）
        let panelVisible = panel.isShown
        let systemInterval = panelVisible
            ? systemSampleInterval
            : max(systemSampleInterval, Self.hiddenSystemSampleInterval)
        var systemGate = MinimumIntervalGate(interval: systemInterval, lastRunAt: lastSystemPoll)
        if systemGate.shouldRun(now: now) {
            lastSystemPoll = now
            systemMonitor?.poll()
        }
        let processInterval = panelVisible ? Self.visibleProcessPollInterval : Self.hiddenProcessPollInterval
        var processGate = MinimumIntervalGate(interval: processInterval, lastRunAt: lastProcessPoll)
        if processGate.shouldRun(now: now) {
            lastProcessPoll = now
            processMonitor.poll()
        }
    }
}
