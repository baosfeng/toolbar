import Foundation
import NetworkMonitorCore

// MARK: - 菜单栏 Token 指标的补拉

/// 菜单栏 Token 指标自刷新 —— 从 `MenuBarManager.swift` 拆出（主文件贴近 15 KiB 上限）
///
/// 问题：菜单栏的 Token 数字读 `HarnessUsageServicing.snapshot()`，而快照只在一轮索引结束后才变。
/// 索引原本只有三条触发路径 —— 后台自动监控定时器（默认关）、面板展开时的全量刷新、设置页手动重扫。
/// 于是默认配置下菜单栏 `Token 713.9M` 会冻在某个值上，直到点开面板才跳一次。
///
/// 修法：只要菜单栏显示着任一 Token 指标，就按 `MenuBarTokenRefresh.interval`（60s）自行补拉一轮增量。
/// 判据（要不要拉）在 Core 的 `MenuBarTokenRefresh`（TestRunner 直接断言），这里只落副作用：
/// 触发一轮后台增量索引、记下时刻；索引完成会发 `AppEvents.harnessUsageChanged`，下一拍自然重画。
extension MenuBarManager {

    /// 到点就补拉一轮（每拍 `update()` 调用一次）
    ///
    /// 幂等：间隔没到直接返回；`refreshIfNeeded` 内部串行、进行中的请求排队合并，不会叠着扫。
    func pullTokenIfNeeded(now: Date) {
        guard let harnessUsage else { return }
        let enabled = displayPreferences.enabledMetrics
        guard MenuBarTokenRefresh.needsPull(enabled: enabled,
                                           lastPullAt: lastTokenPullAt,
                                           now: now) else { return }
        lastTokenPullAt = now
        harnessUsage.refreshIfNeeded()
        logger.debug("菜单栏显示 Token 指标，补拉一轮增量索引")
    }
}
