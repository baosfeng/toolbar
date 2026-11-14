import AppKit
import NetworkMonitorCore

// MARK: - 应用协调器（操作反馈与通知装配）

/// 操作反馈与通知装配 — 音效库 / 播放器 / 系统通知服务 / 触觉的实例化出口
///
/// 拆出原因：AppCoordinator.swift 已贴着单文件 15 KiB 上限，
/// 而这几项共享同一份 NotificationPreferences，集中装配才不会出现两个实例两套状态。
///
/// 实例由组合根持有（不是单例）：调用方从 AppCoordinator 取，遵守依赖倒置。
extension AppCoordinator {

    /// 装配通知与音效链路（偏好改完立即生效：播放器与通知服务每次调用现读偏好）
    ///
    /// 顺序有讲究：先把旧剪贴板开关迁移进事件表（只做一次），
    /// 再构造播放器/通知服务，最后 sync 一遍 ~/Library/Sounds，
    /// 这样「打开 App 就有一份可用的通知音效副本」，不用等第一次发通知。
    func setupNotificationAndFeedback() {
        let preferences = NotificationPreferences(storage: AppContext.shared.storage)
        preferences.migrateLegacyClipboardFlagsIfNeeded()
        notificationPreferences = preferences

        let library = NotificationSoundLibrary(store: NotificationSoundFileStore(
            directory: NotificationSoundFileStore.defaultDirectory()), logger: logger)
        soundLibrary = library
        let player = NotificationSoundPlayer(preferences: preferences, library: library, logger: logger)
        soundPlayer = player

        // 悬空引用自愈：事件还指着一个已不存在的自定义音效时回落到「跟随系统」
        let repaired = preferences.sanitizeCustomSoundReferences(availableFiles: Set(library.customFiles()))
        if !repaired.isEmpty {
            logger.warning("自定义音效缺失，已回落跟随系统：\(repaired.map(\.rawValue).joined(separator: "、"))")
        }

        let installer = NotificationSoundInstaller(store: library.store, logger: logger)
        let service = NotificationCenterService(preferences: preferences,
                                                installer: installer,
                                                logger: logger)
        notificationService = service
        service.syncInstalledSounds()

        soundFeedback = SoundFeedback(player: player)
        hapticFeedback = HapticFeedback(preferences: preferences)
        logger.debug("通知与音效已装配："
                     + NotificationEvent.allCases.map { "\($0.rawValue)=\(preferences.isEnabled($0))" }
            .joined(separator: " "))
    }
}
