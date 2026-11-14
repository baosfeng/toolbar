import AppKit
import NetworkMonitorCore

// MARK: - 应用协调器（操作反馈装配）

/// 操作反馈装配 — 音效与触觉两个服务的实例化出口
///
/// 拆出原因：`AppCoordinator.swift` 已贴着单文件 15 KiB 上限，
/// 而这两项只是把同一份 `ClipboardPreferences` 交给两个服务，独立成文件更清晰。
///
/// 实例由组合根持有（不是单例）：调用方从 `AppCoordinator` 取，遵守依赖倒置。
extension AppCoordinator {

    /// 按剪贴板偏好装配音效与触觉服务（偏好改完立即生效，服务每次调用现读开关）
    func setupFeedback(preferences: ClipboardPreferences) {
        soundFeedback = SoundFeedback(preferences: preferences, logger: logger)
        hapticFeedback = HapticFeedback(preferences: preferences)
        logger.debug("操作反馈已装配：音效=\(preferences.soundEffectsEnabled)，触觉=\(preferences.hapticsEnabled)")
    }
}
