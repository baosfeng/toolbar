import AppKit
import NetworkMonitorCore

// MARK: - 应用协调器（操作反馈与通知装配）

/// 操作反馈与通知装配 — 音效库 / 播放器 / 系统通知服务 / 触觉的实例化出口
///
/// 拆出原因：AppCoordinator.swift 已贴着单文件 15 KiB 上限；这几项共享同一份
/// NotificationPreferences，集中装配才不会出现两个实例两套状态。实例由组合根持有（不是单例）。
extension AppCoordinator {

    /// 装配通知与音效链路（偏好改完立即生效：播放器与通知服务每次调用现读偏好）
    ///
    /// 顺序有讲究：先跑一次性迁移（旧剪贴板开关、旧默认系统音），再构造播放器与通知服务
    /// （音效库装配时顺带铺好内建音），最后 sync 一遍 ~/Library/Sounds。
    func setupNotificationAndFeedback() {
        let preferences = NotificationPreferences(storage: AppContext.shared.storage)
        preferences.migrateLegacyClipboardFlagsIfNeeded()
        // 默认档换成内建音：旧默认系统音一次性改写，须早于第一批声音播放
        NotificationSoundBuiltInMigration.runIfNeeded(preferences: preferences,
                                                     storage: AppContext.shared.storage)
        notificationPreferences = preferences

        let library = NotificationSoundLibrary.makeDefault(logger: logger)
        soundLibrary = library
        let player = NotificationSoundPlayer(preferences: preferences, library: library, logger: logger)
        soundPlayer = player

        // 悬空引用自愈：事件还指着一个已不存在的自定义音效时回落到默认档
        let repaired = preferences.sanitizeCustomSoundReferences(availableFiles: Set(library.customFiles()))
        if !repaired.isEmpty {
            logger.warning("自定义音效缺失，已回落内建音：\(repaired.map(\.rawValue).joined(separator: "、"))")
        }

        let installer = NotificationSoundInstaller(store: library.store,
                                                   builtInStore: library.builtInStore, logger: logger)
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