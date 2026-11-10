import Foundation

// MARK: - 快捷键默认值迁移

/// 截图快捷键默认值迁移 — 纯函数，调用方与测试共用同一判据
///
/// 历史默认值是无修饰键的 F1 / F3。实测在 macOS 27 上这类「单功能键」全局热键
/// 会与系统媒体键 / 屏幕亮度键竞争，注册能成功但按键经常不投递（连按 3 次只到 1 次），
/// 表现为「按了截图键毫无反应」。因此默认值改为带修饰键的组合，
/// 并把偏好里存着的旧默认值一次性迁移到新默认值。
///
/// 判据是白名单而非「所有无修饰键」：用户在设置页录制的组合键一律带修饰键，
/// 但历史偏好可能存有任意值，只迁移一张显式列举的旧默认值表，其余原样保留。
public enum SnipHotKeyMigration {

    /// 「无修饰键 + 该键码」= 旧默认值 → 迁移后的（键码, 修饰键）
    ///
    /// 键码沿用 Carbon 常量数值（kVK_F1 = 122，kVK_F3 = 99），这里写字面量是为了让
    /// Core 不必依赖 Carbon；与 UI 层的 kVK 常量由测试对齐校验。
    static let legacyUnmodifiedDefaults: [UInt32: (keyCode: UInt32, modifiers: UInt32)] = [
        // F1 → ⌃⇧S
        122: (1, 4096 | 512),
        // F3 → ⌃⇧V
        99: (9, 4096 | 512),
    ]

    /// 是否需要迁移
    /// - Parameters:
    ///   - keyCode: 偏好里存的键码
    ///   - modifiers: 偏好里存的修饰键掩码
    public static func needsMigration(keyCode: UInt32, modifiers: UInt32) -> Bool {
        guard modifiers == 0 else { return false }
        return legacyUnmodifiedDefaults[keyCode] != nil
    }

    /// 迁移后的组合；不需要迁移时原样返回
    public static func migrated(keyCode: UInt32, modifiers: UInt32) -> (keyCode: UInt32, modifiers: UInt32) {
        guard modifiers == 0, let replacement = legacyUnmodifiedDefaults[keyCode] else {
            return (keyCode, modifiers)
        }
        return replacement
    }
}
