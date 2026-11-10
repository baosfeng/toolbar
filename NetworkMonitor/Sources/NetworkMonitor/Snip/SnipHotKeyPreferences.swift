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

    var keyCodeKey: String { "snip.hotKey.\(rawValue).keyCode" }
    var modifiersKey: String { "snip.hotKey.\(rawValue).modifiers" }
}

/// 可测试的偏好读写层（不强依赖 concrete storage）
final class SnipHotKeyPreferences {
    private let storage: any KeyValueStorage

    init(storage: any KeyValueStorage = AppContext.shared.storage) {
        self.storage = storage
    }

    /// 读偏好并顺带迁移历史默认值
    ///
    /// 历史默认值是无修饰键的 F1 / F3，那种组合键在 macOS 27 上注册成功但经常不投递
    /// 按键（表现就是「按截图键毫无反应」）。迁移只在读取路径做一次并立即回写，
    /// 用户自己录制过的组合键（都带修饰键）不会被改动。
    func combo(for action: SnipHotKeyAction) -> HotKeyCombo {
        let code = storage.integer(forKey: action.keyCodeKey)
        let modifiers = storage.integer(forKey: action.modifiersKey)
        guard code > 0 else { return action.defaultCombo }
        let stored = SnipHotKeyMigration.migrated(keyCode: UInt32(code), modifiers: UInt32(modifiers))
        let combo = HotKeyCombo(keyCode: stored.keyCode, modifiers: stored.modifiers)
        if stored.keyCode != UInt32(code) || stored.modifiers != UInt32(modifiers) {
            setCombo(combo, for: action)
        }
        return combo
    }

    func setCombo(_ combo: HotKeyCombo, for action: SnipHotKeyAction) {
        storage.set(Int(combo.keyCode), forKey: action.keyCodeKey)
        storage.set(Int(combo.modifiers), forKey: action.modifiersKey)
    }
}
