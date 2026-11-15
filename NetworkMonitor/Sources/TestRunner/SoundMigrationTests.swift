import Foundation
import NetworkMonitorCore

// MARK: - 内建音一次性迁移测试

/// 覆盖「旧版默认档解析出来的系统音 → 内建音」这条一次性迁移：
/// 判据收窄（只动操作反馈类 + 四个旧默认系统音）、标记键幂等、
/// 以及不该动的值（手选系统音 / 自定义文件 / 静音 / 提醒类事件）一个都不误伤。
func runCueSoundMigrationTests() {
    print("\n🧪 Testing 内建音一次性迁移（旧默认值改写 / 幂等 / 不误伤）...")
    testBuiltInMigrationMigratesLegacyDefaults()
    testBuiltInMigrationSkipsOtherValues()
    testBuiltInMigrationIsOneShot()
}

// MARK: - 该迁的

func testBuiltInMigrationMigratesLegacyDefaults() {
    let storage = InMemoryStorage()
    let preferences = NotificationPreferences(storage: storage)
    // 旧版四套默认档解析出来的值：复制 Tink / 粘贴 Pop / 收藏 Glass / 删除 Bottle
    let legacy: [(NotificationEvent, String)] = [
        (.clipboardAction, "Glass"),
        (.snipCaptured, "Tink"),
        (.panelToggle, "Pop"),
        (.transferFinished, "Bottle"),
    ]
    for (event, name) in legacy {
        preferences.setSound(.systemSound(name), for: event)
        assertEqual(NotificationSoundBuiltInMigration.shouldMigrate(event, sound: .systemSound(name)),
                    true, "\(event.rawValue) 的 system:\(name) 属于旧默认值")
    }

    let migrated = NotificationSoundBuiltInMigration.runIfNeeded(preferences: preferences, storage: storage)
    assertEqual(migrated.count, legacy.count, "四条旧默认值全部迁移")
    for (event, _) in legacy {
        assertEqual(preferences.config(for: event).sound, .builtIn,
                    "\(event.rawValue) 迁移后是内建音")
    }
    // 落盘值也要是 builtin 串，不能只改内存里的枚举
    assertEqual(storage.string(forKey: "notify.clipboardAction.sound"), "builtin" as String?,
                "迁移写的是 builtin 存储串")
    assertEqual(storage.bool(forKey: NotificationSoundBuiltInMigration.markerKey), true,
                "迁移标记已落位")
}

// MARK: - 不该迁的

func testBuiltInMigrationSkipsOtherValues() {
    let storage = InMemoryStorage()
    let preferences = NotificationPreferences(storage: storage)
    // 用户手挑的系统音、自定义文件、静音都不动
    preferences.setSound(.systemSound("Sosumi"), for: .clipboardAction)
    preferences.setSound(.customFile("我的叮.aiff"), for: .snipCaptured)
    preferences.setSound(.silent, for: .panelToggle)
    // 提醒类事件即使写着旧默认系统音也不迁（用户更可能主动选的）
    preferences.setSound(.systemSound("Glass"), for: .billingRecovery)
    preferences.setSound(.systemSound("Bottle"), for: .billingAlert)

    assertEqual(NotificationSoundBuiltInMigration.shouldMigrate(.clipboardAction,
                                                                sound: .systemSound("Sosumi")),
                false, "手选系统音不在迁移范围")
    assertEqual(NotificationSoundBuiltInMigration.shouldMigrate(.billingAlert,
                                                                sound: .systemSound("Bottle")),
                false, "额度提醒不在迁移范围")

    let migrated = NotificationSoundBuiltInMigration.runIfNeeded(preferences: preferences, storage: storage)
    assertEqual(migrated, [], "没有一条命中，迁移输出为空")
    assertEqual(preferences.config(for: .clipboardAction).sound, .systemSound("Sosumi"),
                "手选 Sosumi 保留")
    assertEqual(preferences.config(for: .snipCaptured).sound, .customFile("我的叮.aiff"),
                "自定义文件保留")
    assertEqual(preferences.config(for: .panelToggle).sound, .silent, "静音保留")
    assertEqual(preferences.config(for: .billingAlert).sound, .systemSound("Bottle"),
                "额度提醒的旧音名保留")
    assertEqual(preferences.config(for: .billingRecovery).sound, .systemSound("Glass"),
                "额度回升的旧音名保留")
    // 命中为空也要落标记：之后用户手动选回系统音，不该被再次改写
    assertEqual(storage.bool(forKey: NotificationSoundBuiltInMigration.markerKey), true,
                "空迁移也落标记")
}

// MARK: - 幂等

func testBuiltInMigrationIsOneShot() {
    let storage = InMemoryStorage()
    let preferences = NotificationPreferences(storage: storage)
    preferences.setSound(.systemSound("Glass"), for: .clipboardAction)
    assertEqual(NotificationSoundBuiltInMigration.runIfNeeded(preferences: preferences,
                                                              storage: storage),
                [.clipboardAction], "首次迁移命中 clipboardAction")

    // 用户又把这一行改回系统音：标记已落位，不该被二次改写
    preferences.setSound(.systemSound("Glass"), for: .clipboardAction)
    assertEqual(NotificationSoundBuiltInMigration.runIfNeeded(preferences: preferences,
                                                              storage: storage),
                [], "迁过之后再跑是 noop")
    assertEqual(preferences.config(for: .clipboardAction).sound, .systemSound("Glass"),
                "用户迁移后手选的值被尊重")

    // 换一份偏好实例（同存储）也认标记：启动多次只迁一次
    let another = NotificationPreferences(storage: storage)
    assertEqual(NotificationSoundBuiltInMigration.runIfNeeded(preferences: another, storage: storage),
                [], "换实例仍认标记")
}
