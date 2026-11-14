import Foundation

// MARK: - 单个事件的合并配置

/// 一个事件生效中的配置 — 读偏好后的合并结果（未写过的项取事件默认值）
public struct NotificationEventConfig: Equatable, Sendable {
    /// 总开关
    public var enabled: Bool
    /// 声音选择
    public var sound: NotificationSoundSelection
    /// 提醒方式（仅 postsSystemNotification 的事件有效）
    public var presentation: NotificationPresentation
    /// 触觉档位
    public var haptic: NotificationHaptic

    public init(enabled: Bool,
                sound: NotificationSoundSelection,
                presentation: NotificationPresentation,
                haptic: NotificationHaptic) {
        self.enabled = enabled
        self.sound = sound
        self.presentation = presentation
        self.haptic = haptic
    }
}

// MARK: - 通知偏好

/// 通知与音效偏好 — 事件表六行的全部键名与默认值合并逻辑
///
/// 只做键值读写与纯合并，不碰 UI、不碰 AVFoundation：
/// 播放器与通知服务都从这里取「生效配置」，所以改完设置立即生效（无需回调）。
/// 线程模型与 TransferPreferences 一致：内部只有轻量键值访问，可跨线程调用。
public final class NotificationPreferences: @unchecked Sendable {

    // MARK: 旧键（迁移用）

    /// 剪贴板旧反馈开关（拆分类之前的两把键，只用于一次性迁移）
    public enum LegacyClipboardKey {
        /// 旧「操作音效」开关
        public static let soundEffects = "clipboard.soundEffectsEnabled"
        /// 旧「触觉反馈」开关
        public static let haptics = "clipboard.hapticsEnabled"
    }

    private enum Key {
        static let inAppVolume = "notify.inAppVolume"
        static let migratedFlag = "notify.migratedFromClipboardFlags"

        static func enabled(_ event: NotificationEvent) -> String {
            "notify.\(event.rawValue).enabled"
        }
        static func sound(_ event: NotificationEvent) -> String {
            "notify.\(event.rawValue).sound"
        }
        static func presentation(_ event: NotificationEvent) -> String {
            "notify.\(event.rawValue).presentation"
        }
        static func haptic(_ event: NotificationEvent) -> String {
            "notify.\(event.rawValue).haptic"
        }

        /// 恢复默认时要清的全部键
        static var all: [String] {
            var keys = [inAppVolume, migratedFlag]
            for event in NotificationEvent.allCases {
                keys.append(contentsOf: [enabled(event), sound(event),
                                         presentation(event), haptic(event)])
            }
            return keys
        }
    }

    private let storage: any KeyValueStorage

    public init(storage: any KeyValueStorage = AppContext.shared.storage) {
        self.storage = storage
    }

    // MARK: - 应用内音量

    /// 应用内提示音音量（0...1；未写过或超出范围时按 1）
    ///
    /// 只作用于 NSSound 播放的应用内提示音，系统通知音量由系统「声音」设置决定，这里改不了。
    public var inAppVolume: Double {
        get {
            guard storage.object(forKey: Key.inAppVolume) != nil else { return 1 }
            let value = storage.double(forKey: Key.inAppVolume)
            return min(1, max(0, value))
        }
        set { storage.set(min(1, max(0, newValue)), forKey: Key.inAppVolume) }
    }

    // MARK: - 事件配置

    /// 某事件当前生效的完整配置（未写过的项逐个回落到事件默认值）
    public func config(for event: NotificationEvent) -> NotificationEventConfig {
        let fallback = event.defaultConfig
        let enabled: Bool = storage.object(forKey: Key.enabled(event)) == nil
            ? fallback.enabled
            : storage.bool(forKey: Key.enabled(event))
        let sound = NotificationSoundSelection(
            storageValue: storage.string(forKey: Key.sound(event)) ?? fallback.sound.storageValue)
        let presentation = NotificationPresentation(
            rawValue: storage.string(forKey: Key.presentation(event)) ?? "")
            ?? fallback.presentation
        let haptic = NotificationHaptic(rawValue: storage.string(forKey: Key.haptic(event)) ?? "")
            ?? fallback.haptic
        return NotificationEventConfig(enabled: enabled, sound: sound,
                                       presentation: presentation, haptic: haptic)
    }

    /// 事件开关
    public func isEnabled(_ event: NotificationEvent) -> Bool { config(for: event).enabled }

    /// 写事件开关
    public func setEnabled(_ enabled: Bool, for event: NotificationEvent) {
        storage.set(enabled, forKey: Key.enabled(event))
    }

    /// 写声音选择
    public func setSound(_ sound: NotificationSoundSelection, for event: NotificationEvent) {
        storage.set(sound.storageValue, forKey: Key.sound(event))
    }

    /// 写提醒方式
    public func setPresentation(_ presentation: NotificationPresentation, for event: NotificationEvent) {
        storage.set(presentation.rawValue, forKey: Key.presentation(event))
    }

    /// 写触觉档位
    public func setHaptic(_ haptic: NotificationHaptic, for event: NotificationEvent) {
        storage.set(haptic.rawValue, forKey: Key.haptic(event))
    }

    // MARK: - 恢复默认

    /// 恢复默认 — 清掉本模块写入的全部键（音量回 1、六个事件回出厂配置）
    public func resetToDefaults() {
        Key.all.forEach { storage.removeObject(forKey: $0) }
        // 迁移标记重新置位：否则清空后旧剪贴板开关会再次被迁移回来，用户会以为「恢复默认没生效」
        storage.set(true, forKey: Key.migratedFlag)
    }

    // MARK: - 悬空引用自愈

    /// 修掉指向「已经不存在的自定义音效」的事件，返回被修的事件（无则空）
    ///
    /// 触发场景：用户在 Finder 里手删了音效文件、或备份还原后目录不完整。
    /// 不修的话事件会一直引用一个不存在的文件：应用内提示音静默、系统通知回落到默认音，
    /// 而设置页那一行仍显示「自定义 · 某某」，用户看不出问题在哪。
    @discardableResult
    public func sanitizeCustomSoundReferences(availableFiles: Set<String>) -> [NotificationEvent] {
        var repaired: [NotificationEvent] = []
        for event in NotificationEvent.allCases {
            guard case .customFile(let file) = config(for: event).sound else { continue }
            guard !availableFiles.contains(file) else { continue }
            setSound(.systemDefault, for: event)
            repaired.append(event)
        }
        return repaired
    }

    // MARK: - 旧键迁移

    /// 把拆分类之前的两个剪贴板开关迁移成 clipboardAction 一行的配置（只做一次）
    ///
    /// 迁移口径：
    /// - 旧「操作音效」= 关（默认）时不需要迁移，新默认同样是关；
    ///   但用户若曾改成开，必须迁移过去，否则升级后他的开关会凭空变回关。
    /// - 旧「触觉反馈」默认开；只有用户显式关掉过才落到新行的「关闭」，开的情况用新默认（标准）。
    public func migrateLegacyClipboardFlagsIfNeeded() {
        guard storage.object(forKey: Key.migratedFlag) == nil else { return }
        if storage.object(forKey: Key.enabled(.clipboardAction)) == nil,
           let legacy = storage.object(forKey: LegacyClipboardKey.soundEffects) {
            _ = legacy
            setEnabled(storage.bool(forKey: LegacyClipboardKey.soundEffects), for: .clipboardAction)
        }
        if storage.object(forKey: Key.haptic(.clipboardAction)) == nil,
           storage.object(forKey: LegacyClipboardKey.haptics) != nil,
           !storage.bool(forKey: LegacyClipboardKey.haptics) {
            setHaptic(.off, for: .clipboardAction)
        }
        storage.set(true, forKey: Key.migratedFlag)
    }
}
