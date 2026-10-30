import AppKit
import NetworkMonitorCore

// MARK: - 应用协调器（系统监控装配）

/// 系统监控链路装配 — 独立成扩展，避免组合根主文件继续膨胀（已贴近 15 KiB 上限）
extension AppCoordinator {

    /// 装配系统指标采样服务（唯一允许 new 具体实现的位置就在组合根）
    ///
    /// 采样周期取偏好，与服务 / 面板共用同一份 `SystemMonitorPreferences` 实例；
    /// 采样由菜单栏 1 秒轮询链按该周期节流驱动（见 `MenuBarManager.update`），
    /// 因此这里不调用 `SystemMonitor.start()`，避免出现两套定时器重复采样。
    func makeSystemMonitor() -> (monitor: any SystemMonitoringService,
                                 preferences: SystemMonitorPreferences) {
        let preferences = SystemMonitorPreferences()
        let monitor = SystemMonitor(interval: preferences.sampleInterval, logger: logger)
        return (monitor, preferences)
    }
}
