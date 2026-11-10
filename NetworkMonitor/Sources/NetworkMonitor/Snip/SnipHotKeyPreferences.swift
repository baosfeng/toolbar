import AppKit
import Carbon
import NetworkMonitorCore

// MARK: - 截图快捷键偏好

/// 截图 / 贴图的全局快捷键动作（持久化在 KeyValueStorage）
///
/// 与剪贴板的 `panelToggleHotKey` 共用同一套 `HotKeyCombo` 编码（keyCode + modifiers）；
/// 未设置时按默认组合键回落。
enum SnipHotKeyAction: String, CaseIterable {
    case screenshot
    case pin
    case delayedScreenshot
    case hidePins
    case settings
    case whiteboard

    var displayName: String {
        switch self {
        case .screenshot: return "截图"
        case .pin: return "贴图"
        case .delayedScreenshot: return "延时截图"
        case .hidePins: return "隐藏贴图"
        case .settings: return "打开设置"
        case .whiteboard: return "白板"
        }
    }

    var defaultCombo: HotKeyCombo {
        switch self {
        // 默认一律带修饰键：无修饰键的单功能键（F1/F3）在 macOS 27 会与系统媒体键
        // 抢同一通道，注册成功但经常不投递按键（实测连按 3 次只到 1 次）
        case .screenshot: return HotKeyCombo(keyCode: UInt32(kVK_ANSI_S),
                                            modifiers: UInt32(controlKey | shiftKey))
        case .pin: return HotKeyCombo(keyCode: UInt32(kVK_ANSI_V),
                                     modifiers: UInt32(controlKey | shiftKey))
        case .delayedScreenshot: return HotKeyCombo(keyCode: UInt32(kVK_ANSI_D),
                                                  modifiers: UInt32(optionKey | shiftKey))
        case .hidePins: return HotKeyCombo(keyCode: UInt32(kVK_F3), modifiers: UInt32(shiftKey))
        case .settings: return HotKeyCombo(keyCode: UInt32(kVK_ANSI_Comma),
                                          modifiers: UInt32(optionKey | shiftKey))
        case .whiteboard: return HotKeyCombo(keyCode: UInt32(kVK_ANSI_W),
                                            modifiers: UInt32(optionKey | shiftKey))
        }
    }

    /// 键码存储键（键名规则收敛在 Core 的 SnipHotKeyKeyNames，读写与测试同源）
    var keyCodeKey: String { SnipHotKeyKeyNames.keyCodeKey(actionRawValue: rawValue) }
    /// 修饰键掩码存储键
    var modifiersKey: String { SnipHotKeyKeyNames.modifiersKey(actionRawValue: rawValue) }
}

/// 可测试的偏好读写层（不强依赖 concrete storage）
final class SnipHotKeyPreferences {
    private let storage: any KeyValueStorage

    init(storage: any KeyValueStorage = AppContext.shared.storage) {
        self.storage = storage
    }

    /// 读偏好并顺带迁移历史默认值
    ///
    /// 判据本身在 Core 的 `SnipHotKeyComboResolver`（纯函数），这里只做委托与回写，
    /// 让 TestRunner 能直接断言口径而不必 import 可执行目标。
    ///
    /// 两条纪律：
    /// 1. **存在性看「存储里有没有这个键」，不看值大小**。历史上这里用 `code > 0`，
    ///    而 A 键的 keyCode 恰好是 0，⌘⌥A 这类用户自己录制的组合被误判成「没设置过」，
    ///    于是回落默认的 ⌃⇧S、并在注册成功后把默认值写回存储 —— 用户的设置被永久覆盖。
    ///    keyCode 0 是合法键码（kVK_ANSI_A = 0），修饰键 0 也可以是用户录制的单键组合，
    ///    所以「值非零」不能当存在性。
    /// 2. **读路径不得回写默认值**。存储缺键时只返回 `defaultCombo`，绝不 setCombo：
    ///    把「我根本没设置过」固化成一条显式默认值，之后默认值再调整这个用户就永远跟不上；
    ///    而且读一次写一次会让「自定义了下次又被还原」这类现象无法排查。
    ///    只有命中旧默认值白名单（`didMigrate`）才回写一次，因为那是把历史默认值换成新默认值，
    ///    属于迁移而不是「补一个默认值」。真正的「写回」只发生在注册成功之后
    ///    （`registerSnipHotKey` 写回实际注册成功的组合），那是真实生效值，不是读路径产物。
    func combo(for action: SnipHotKeyAction) -> HotKeyCombo {
        let fallback = SnipHotKeyComboValue(keyCode: action.defaultCombo.keyCode,
                                            modifiers: action.defaultCombo.modifiers)
        let resolution = SnipHotKeyComboResolver.resolve(storage: storage,
                                                         keyCodeKey: action.keyCodeKey,
                                                         modifiersKey: action.modifiersKey,
                                                         fallback: fallback)
        let combo = HotKeyCombo(keyCode: resolution.combo.keyCode, modifiers: resolution.combo.modifiers)
        if resolution.didMigrate {
            setCombo(combo, for: action)
        }
        return combo
    }

    func setCombo(_ combo: HotKeyCombo, for action: SnipHotKeyAction) {
        storage.set(Int(combo.keyCode), forKey: action.keyCodeKey)
        storage.set(Int(combo.modifiers), forKey: action.modifiersKey)
    }
}
