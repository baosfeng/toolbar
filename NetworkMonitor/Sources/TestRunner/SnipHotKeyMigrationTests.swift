import Foundation
import NetworkMonitorCore

// MARK: - 截图快捷键默认值迁移（回归：无修饰键功能键热键在 macOS 27 上不投递）

func runSnipHotKeyMigrationTests() {
    print("🧪 Testing snip hotkey migration...")

    // 旧默认值：无修饰键的 F1 / F3（Carbon kVK_F1 = 122、kVK_F3 = 99）
    assertEqual(SnipHotKeyMigration.needsMigration(keyCode: 122, modifiers: 0), true, "F1 旧默认值需要迁移")
    assertEqual(SnipHotKeyMigration.needsMigration(keyCode: 99, modifiers: 0), true, "F3 旧默认值需要迁移")

    // 迁移后必须带修饰键，且与原键码不同（否则等于没迁移）
    let migratedF1 = SnipHotKeyMigration.migrated(keyCode: 122, modifiers: 0)
    assertEqual(migratedF1.keyCode, 1, "F1 迁移为 S 键（kVK_ANSI_S = 1）")
    assertEqual(migratedF1.modifiers, 4096 | 512, "F1 迁移为 ⌃⇧ 修饰键")
    let migratedF3 = SnipHotKeyMigration.migrated(keyCode: 99, modifiers: 0)
    assertEqual(migratedF3.keyCode, 9, "F3 迁移为 V 键（kVK_ANSI_V = 9）")
    assertEqual(migratedF3.modifiers, 4096 | 512, "F3 迁移为 ⌃⇧ 修饰键")

    // 用户自己录制过的组合键（带修饰键）一律不动
    assertEqual(SnipHotKeyMigration.needsMigration(keyCode: 122, modifiers: 2048), false,
                "⌥F1 是用户自己录制的，不迁移")
    assertEqual(SnipHotKeyMigration.needsMigration(keyCode: 0, modifiers: 0), false, "键码 0 = 未设置，不迁移")
    assertEqual(SnipHotKeyMigration.needsMigration(keyCode: 3, modifiers: 0), false,
                "F 以外的无修饰键不在迁移白名单")
    assertEqual(SnipHotKeyMigration.migrated(keyCode: 3, modifiers: 0).keyCode, 3, "白名单外原样返回")

    // 乱序：无修饰键但带大写位（Carbon 修饰键里不含 0）仍按无修饰键处理
    assertEqual(SnipHotKeyMigration.migrated(keyCode: 122, modifiers: 0).modifiers, 4096 | 512,
                "重复调用结果一致（幂等）")

    print("✅ 截图快捷键默认值迁移测试通过")
}
