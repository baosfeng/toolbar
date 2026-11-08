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
        case .screenshot: return HotKeyCombo(keyCode: UInt32(kVK_F1), modifiers: 0)
        case .pin: return HotKeyCombo(keyCode: UInt32(kVK_F3), modifiers: 0)
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

    func combo(for action: SnipHotKeyAction) -> HotKeyCombo {
        let code = storage.integer(forKey: action.keyCodeKey)
        let modifiers = storage.integer(forKey: action.modifiersKey)
        guard code > 0 else { return action.defaultCombo }
        return HotKeyCombo(keyCode: UInt32(code), modifiers: UInt32(modifiers))
    }

    func setCombo(_ combo: HotKeyCombo, for action: SnipHotKeyAction) {
        storage.set(Int(combo.keyCode), forKey: action.keyCodeKey)
        storage.set(Int(combo.modifiers), forKey: action.modifiersKey)
    }
}
