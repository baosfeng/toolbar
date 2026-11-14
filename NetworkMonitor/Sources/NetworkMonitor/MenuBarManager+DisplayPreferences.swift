import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 菜单栏管理器（显示偏好订阅）

/// 「菜单栏显示」偏好的事件驱动 —— 从 `MenuBarManager.swift` 拆出（主文件接近单文件 15 KiB 上限）
///
/// 设置页写完偏好发 `AppEvents.menuBarDisplayChanged`，这里重建定时器并立刻重渲染，
/// 不用等下一个刷新周期、也不用重启应用。定时器与状态栏仍是主类职责，这里只调它的入口。
extension MenuBarManager {

    /// 订阅菜单栏显示偏好变更（主类 init 末尾调用，只注册一次）
    func observeDisplayPreferenceChanges() {
        displayPreferencesObserver = NotificationCenter.default.addObserver(
            forName: AppEvents.menuBarDisplayChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.applyDisplayPreferences()
            }
        }
    }

    /// 应用最新偏好：刷新周期变了就重建定时器，然后立即重渲染一次状态栏
    ///
    /// 周期**取自渲染帧率档**（标准 1s / 极致 0.5s / 省电 2s），不再读「间隔」偏好：
    /// 档位与间隔是同一维度上的两个旋钮，并存会出现「选了省电还是 1 秒刷」的矛盾。
    /// 系统指标采样周期同样随档位改写（`systemSampleInterval`）。
    /// - Parameter tierOverride: 显式档位（结构自证与测试用）；nil = 读偏好（生产路径）
    func applyDisplayPreferences(tierOverride: RenderTier? = nil) {
        let tier = tierOverride ?? appearancePreferences.renderTier
        let profile = RenderTierLogic.profile(for: tier)
        systemSampleInterval = profile.sampleInterval
        let desired = profile.tickInterval
        // 周期没变就保留正在跑的定时器，避免每次改布局都把刷新节拍重置一遍
        if MenuBarDisplayLogic.needsTimerRebuild(currentInterval: timerInterval, desiredInterval: desired) {
            setupTimer(interval: desired)
        } else {
            update()
        }
        logger.info("渲染档生效：\(RenderTierLogic.summary(for: tier))")
    }
}
