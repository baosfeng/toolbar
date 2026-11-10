import Foundation

// MARK: - 截图快捷键组合解析（存储值 → 组合键）

/// 组合键的「键码 + 修饰键」裸值
///
/// Core 不依赖 Carbon / AppKit（那两个字眼只允许出现在可执行目标），所以这里用裸数值，
/// 与 UI 层的 `HotKeyCombo` 由调用方逐字段搬运。
public struct SnipHotKeyComboValue: Equatable, Sendable {
    public let keyCode: UInt32
    public let modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

/// 一次读取的结论：拿到哪个组合、是不是回落值、要不要回写迁移结果
public struct SnipHotKeyComboResolution: Equatable, Sendable {
    /// 最终生效的组合（迁移后 / 原样 / 默认值）
    public let combo: SnipHotKeyComboValue
    /// true = 存储里缺键，combo 是调用方传进来的默认值
    public let usedFallback: Bool
    /// true = 命中了旧默认值白名单并换算过，调用方应把结果回写一次
    public let didMigrate: Bool

    public init(combo: SnipHotKeyComboValue, usedFallback: Bool, didMigrate: Bool) {
        self.combo = combo
        self.usedFallback = usedFallback
        self.didMigrate = didMigrate
    }
}

/// 偏好读路径的判据 — 纯函数，调用方与测试共用同一套口径
public enum SnipHotKeyComboResolver {

    /// 从存储读出组合键
    ///
    /// **存在性判据 = 「存储里有没有这个键」**（`object(forKey:)` 非 nil），两个键都要在，
    /// 任一缺失才回落调用方给的默认组合。不能用 `keyCode > 0` 判「是否设置过」：
    /// keyCode 0 是完全合法的键码（kVK_ANSI_A = 0），⌘⌥A 这类用户自己录制的组合会被
    /// 误判成「没设置过」，然后回落默认值、并在注册成功后被写回存储，用户的设置被永久覆盖。
    /// 同理也不能拿「值是否非零」当存在性：修饰键为 0 也可能是用户录制的单键组合。
    ///
    /// **读路径只读不写**：`usedFallback` 为 true 时绝不把默认值写回存储——否则「我根本
    /// 没设置过」会被固化成一个显式的默认值，之后默认值再调整就再也跟不上这个用户；
    /// 只有 `didMigrate` 为 true（命中旧默认值白名单）才由调用方回写一次。
    ///
    /// - Parameters:
    ///   - storage: 注入的键值存储（禁止在这里自行取 UserDefaults.standard）
    ///   - keyCodeKey: 键码的存储键
    ///   - modifiersKey: 修饰键掩码的存储键
    ///   - fallback: 存储缺键时使用的默认组合
    public static func resolve(storage: any KeyValueStorage,
                               keyCodeKey: String,
                               modifiersKey: String,
                               fallback: SnipHotKeyComboValue) -> SnipHotKeyComboResolution {
        guard storage.object(forKey: keyCodeKey) != nil,
              storage.object(forKey: modifiersKey) != nil else {
            return SnipHotKeyComboResolution(combo: fallback, usedFallback: true, didMigrate: false)
        }
        let rawKeyCode = storage.integer(forKey: keyCodeKey)
        let rawModifiers = storage.integer(forKey: modifiersKey)
        // 损坏值（负数）不能直接转 UInt32（会 trapping），按「未设置」回落
        guard rawKeyCode >= 0, rawModifiers >= 0 else {
            return SnipHotKeyComboResolution(combo: fallback, usedFallback: true, didMigrate: false)
        }
        let migrated = SnipHotKeyMigration.migrated(keyCode: UInt32(rawKeyCode),
                                                    modifiers: UInt32(rawModifiers))
        let didMigrate = migrated.keyCode != UInt32(rawKeyCode) || migrated.modifiers != UInt32(rawModifiers)
        return SnipHotKeyComboResolution(
            combo: SnipHotKeyComboValue(keyCode: migrated.keyCode, modifiers: migrated.modifiers),
            usedFallback: false,
            didMigrate: didMigrate
        )
    }
}

// MARK: - 存储键名

/// 偏好键名 — 读写两侧与测试共用同一口径，避免字符串散落
///
/// 键名规则：`snip.hotKey.<action>.keyCode` / `snip.hotKey.<action>.modifiers`
public enum SnipHotKeyKeyNames {
    /// 键码的存储键
    public static func keyCodeKey(actionRawValue: String) -> String {
        "snip.hotKey.\(actionRawValue).keyCode"
    }

    /// 修饰键掩码的存储键
    public static func modifiersKey(actionRawValue: String) -> String {
        "snip.hotKey.\(actionRawValue).modifiers"
    }
}
