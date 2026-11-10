import AppKit
import CoreGraphics
import NetworkMonitorUI

// MARK: - 按键桥（系统层按键 → 纯逻辑口径，从主类拆出守住门禁）

extension SnipKeyCommandResolver.Modifiers {

    /// 把 AppKit 的修饰键集合转成纯逻辑口径
    ///
    /// 只保留会改变覆盖层语义的四个修饰键：⌘ 与 ⌘⇧ 组合决定复制 / 保存 / 撤销，
    /// 其余（CapsLock、Fn 等）与截图无关，丢掉能避免解析分支被无意义组合淹没。
    init(nsEventFlags flags: NSEvent.ModifierFlags) {
        self.init(command: flags.contains(.command),
                  shift: flags.contains(.shift),
                  control: flags.contains(.control),
                  option: flags.contains(.option))
    }

    /// 把 CGEventTap 回调里的修饰键转成同一口径
    ///
    /// 回调跑在事件 tap 线程，不能在那里构造 NSEvent（AppKit 对象只在主线程安全），
    /// 因此直接从 CGEventFlags 取位。
    init(cgEventFlags flags: CGEventFlags) {
        self.init(command: flags.contains(.maskCommand),
                  shift: flags.contains(.maskShift),
                  control: flags.contains(.maskControl),
                  option: flags.contains(.maskAlternate))
    }
}

// MARK: - CGEvent 字符解码

enum SnipCGEventCharacters {

    /// 取按键对应的字符（字母键受键盘布局影响，必须由系统解码，不能硬编码键码）
    static func text(of event: CGEvent) -> String? {
        var buffer = [UniChar](repeating: 0, count: 8)
        var length = 0
        event.keyboardGetUnicodeString(maxStringLength: buffer.count,
                                       actualStringLength: &length,
                                       unicodeString: &buffer)
        guard length > 0, length <= buffer.count else { return nil }
        let text = String(utf16CodeUnits: buffer, count: length)
        // 系统在无对应字符时给 0xFFFF（私有占位符），按「无字符」处理
        return text.unicodeScalars.contains { $0.value >= 0xF700 && $0.value <= 0xF8FF } ? nil : text
    }
}
