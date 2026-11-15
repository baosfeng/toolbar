import Foundation

// MARK: - 内建音一次性迁移

/// 内建音一次性迁移 — 把「旧版默认档解析出来的系统音」改写成内建音
///
/// 为什么需要它：默认档从「跟随系统」换成「内建（咔哒）」时，老配置里已经**写过**
/// 解析结果（`system:Glass` / `system:Tink` / `system:Pop` / `system:Bottle`），
/// 不迁就等于老用户升级后仍听系统音——需求对这批人没生效。
///
/// 判据刻意收窄（宁可少迁，不可误迁）：
/// - 只动**操作反馈类**事件（剪贴板 / 截图 / 面板 / 传输）——提醒类本来就该有存在感，
///   用户对额度提醒的声音偏好更可能是主动选的；
/// - 只动**旧版三套默认档解析出来**的那四个值，用户手挑的其它系统音（Hero / Sosumi……）、
///   自定义文件、静音一律不动。
public enum NotificationSoundBuiltInMigration {

    /// 一次性标记键（迁过就不再迁，改回系统音也不会被二次改写）
    public static let markerKey = "notify.sound.builtinMigrated"

    /// 参与迁移的事件 — 操作反馈类五个 cue 都落在这些行上
    public static let migratedEvents: [NotificationEvent] = [
        .clipboardAction, .snipCaptured, .panelToggle, .transferFinished,
    ]

    /// 旧版默认档解析出来的系统音名（复制 Tink / 粘贴 Pop / 收藏 Glass / 删除 Bottle）
    public static let legacyDefaultSystemSounds: Set<String> = ["Tink", "Pop", "Glass", "Bottle"]

    /// 纯判定：这个事件的声音该不该改写成内建音
    public static func shouldMigrate(_ event: NotificationEvent,
                                     sound: NotificationSoundSelection) -> Bool {
        guard migratedEvents.contains(event) else { return false }
        guard case .systemSound(let name) = sound else { return false }
        return legacyDefaultSystemSounds.contains(name)
    }

    /// 执行迁移，返回被改写的事件（空 = 无需迁移或已经迁过）
    @discardableResult
    public static func runIfNeeded(preferences: NotificationPreferences,
                                   storage: any KeyValueStorage) -> [NotificationEvent] {
        guard !storage.bool(forKey: markerKey) else { return [] }
        var migrated: [NotificationEvent] = []
        for event in migratedEvents {
            let sound = preferences.config(for: event).sound
            guard shouldMigrate(event, sound: sound) else { continue }
            preferences.setSound(.builtIn, for: event)
            migrated.append(event)
        }
        // 标记无条件落位：即使这次没有一条命中，也不该在用户之后手动选回系统音时再改回去
        storage.set(true, forKey: markerKey)
        return migrated
    }
}
