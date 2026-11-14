import Foundation

// MARK: - 采样节拍（随面板可见性降频）

/// 状态栏 1 秒刷新链里的两路采样节流
///
/// 拆出来两个理由：
/// 1. 面板收起时系统指标与进程榜都没有观察者——系统采样从 1 秒降到 5 秒、
///    nettop 进程采样从 3 秒降到 15 秒（nettop 每次 fork 实测 0.3–0.65% CPU）；
/// 2. MenuBarManager.swift 已到单文件字节上限，节流逻辑独立成扩展文件。
///
/// 状态栏仍需的网速由 monitor.poll() 提供，不走这里，所以收起时状态栏照常每秒刷新。
extension MenuBarManager {

    /// 面板收起时的系统采样周期下限（秒）：保留告警阈值所需的灵敏度，又能去掉无人看的帧
    private static let hiddenSystemSampleInterval: TimeInterval = 5
    /// 面板展开时的进程采样周期（秒）：与 ProcessNetworkMonitor 内部节流对齐
    private static let visibleProcessPollInterval: TimeInterval = 3
    /// 面板收起时的进程采样周期（秒）：nettop 每次 fork 都有实打实的 CPU 成本
    private static let hiddenProcessPollInterval: TimeInterval = 15

    /// 按面板可见性与各自节流周期触发一次采样
    func pollSamplingIfNeeded(now: Date) {
        let panelVisible = panel.isShown
        let systemInterval = panelVisible
            ? systemSampleInterval
            : max(systemSampleInterval, Self.hiddenSystemSampleInterval)
        if now.timeIntervalSince(lastSystemPoll) >= systemInterval {
            lastSystemPoll = now
            systemMonitor?.poll()
        }
        let processInterval = panelVisible ? Self.visibleProcessPollInterval : Self.hiddenProcessPollInterval
        if now.timeIntervalSince(lastProcessPoll) >= processInterval {
            lastProcessPoll = now
            processMonitor.poll()
        }
    }
}
