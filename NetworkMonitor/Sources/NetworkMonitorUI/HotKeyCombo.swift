import Carbon
import Foundation

// MARK: - 全局快捷键组合

/// 全局快捷键组合 — Carbon 键码 + Carbon 修饰键位掩码
///
/// 与偏好层共用：keyCode / modifiers 直接以整数持久化，避免平台枚举的编码不稳定。
///
/// 归属：NetworkMonitorUI（纯值 + 展示口径）。放这里的理由：
/// 1. `displayString` 是展示逻辑（"⌥⌘V" 这类排版），正是本 target「展示纯逻辑」的职责；
/// 2. Core 明确不依赖 Carbon（`SnipHotKeyComboValue` 用裸数值、由调用方逐字段搬运），
///    组合键展示要读 kVK_* / cmdKey 这些 Carbon 常量，放在 Core 会打破那条约束；
/// 3. TestRunner 直接 import 本 target，组合键排版与修饰键判定可以被断言。
/// 绕不开 AppKit 的那一段（NSEvent.ModifierFlags → Carbon 位掩码）留在 App 的
/// GlobalHotKey.swift 里，本 target 不 import AppKit。
public struct HotKeyCombo: Equatable, Sendable {
    /// Carbon 虚拟键码（kVK_*）
    public var keyCode: UInt32
    /// Carbon 修饰键位掩码（cmdKey / shiftKey / optionKey / controlKey）
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// 默认唤起组合：⌥⌘V（keyCode 9 = kVK_ANSI_V）
    public static let defaultPanelToggle = HotKeyCombo(keyCode: 9, modifiers: UInt32(cmdKey | optionKey))

    /// 是否带至少一个修饰键（单键不允许作为全局热键）
    public var hasModifier: Bool { modifiers & UInt32(cmdKey | shiftKey | optionKey | controlKey) != 0 }

    /// 展示文本，如 "⌥⌘V"（组合顺序固定为 ⌃⌥⇧⌘）
    public var displayString: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + Self.keyLabel(keyCode)
    }

    /// 键码转展示字符（仅覆盖常用键，未知键码回退为「键码 N」）
    private static func keyLabel(_ keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_Grave: return "\u{60}"
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_Equal: return "="
        case kVK_Space: return "空格"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Escape: return "⎋"
        default: return "键码 \(keyCode)"
        }
    }
}
