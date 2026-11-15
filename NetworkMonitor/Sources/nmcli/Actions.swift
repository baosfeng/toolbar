import AppKit
import ApplicationServices
import CoreGraphics

// MARK: - 点击 / 悬停 / 键盘

enum Actions {

    // MARK: 点击

    /// 按元素点击：AXPress 优先，失败回退到坐标点击
    ///
    /// 为什么优先 AXPress：菜单栏状态项（AXMenuExtra）能直接接受 `kAXPressAction`
    /// 并真的打开面板，且不受状态项宽度实时变化影响；自绘元素往往没有 AXPress，
    /// 这时才需要回退到它上报的 bounds 中心做坐标点击。
    @discardableResult
    static func press(_ node: AXNode) -> Bool {
        guard node.actions.contains(kAXPressAction as String) else { return false }
        return AXUIElementPerformAction(node.element, kAXPressAction as CFString) == .success
    }

    /// 裸坐标点击：移动 → 按下 → 抬起，鼠标事件走 cghidEventTap（与真实点击同一条链路）
    static func click(at point: CGPoint) {
        move(to: point)
        usleep(60_000)
        post(.leftMouseDown, at: point)
        usleep(40_000)
        post(.leftMouseUp, at: point)
    }

    /// 移动光标并保持（悬停浮层 / hover 高亮验收用）
    static func hover(at point: CGPoint, holdMilliseconds: Int) {
        // 先落到目标上方 4pt 再进目标：macOS 的 mouseEntered 只认「跨进边界」的移动，
        // 一次性 warp 到边界内有时不会触发追踪区
        move(to: CGPoint(x: point.x, y: point.y - 4))
        usleep(60_000)
        move(to: point)
        usleep(UInt32(max(0, holdMilliseconds)) * 1000)
    }

    static func move(to point: CGPoint) {
        post(.mouseMoved, at: point)
    }

    private static func post(_ type: CGEventType, at point: CGPoint) {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }

    // MARK: 键盘

    /// 键入文本：逐字符走 Unicode 事件，不依赖键盘布局
    static func type(_ text: String) {
        for scalar in text.unicodeScalars {
            var unit = UniChar(scalar.value > 0xFFFF ? 0xFFFD : scalar.value)
            let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
            down?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unit)
            down?.post(tap: .cghidEventTap)
            let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
            up?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unit)
            up?.post(tap: .cghidEventTap)
            usleep(8_000)
        }
    }

    /// 组合键：`cmd+w` / `esc` / `enter` / `cmd+shift+4`
    static func key(_ combo: String) throws {
        let parts = combo.lowercased().split(separator: "+").map(String.init)
        guard let keyName = parts.last else { throw CLIError("空按键组合") }
        var flags: CGEventFlags = []
        for modifier in parts.dropLast() {
            switch modifier {
            case "cmd", "command": flags.insert(.maskCommand)
            case "opt", "alt", "option": flags.insert(.maskAlternate)
            case "ctrl", "control": flags.insert(.maskControl)
            case "shift": flags.insert(.maskShift)
            case "fn": flags.insert(.maskSecondaryFn)
            default: throw CLIError("未知修饰键「\(modifier)」（支持 cmd/opt/ctrl/shift/fn）")
            }
        }
        guard let code = KeyCode.virtualKey(for: keyName) else {
            throw CLIError("未知按键「\(keyName)」")
        }
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
        down?.flags = flags
        down?.post(tap: .cghidEventTap)
        usleep(30_000)
        let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
        up?.flags = flags
        up?.post(tap: .cghidEventTap)
    }
}

/// 键名 → 虚拟键码（只收验收常用键；字母数字走 ANSI 表）
enum KeyCode {
    private static let table: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26,
        "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
        "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45,
        "m": 46, ".": 47, "tab": 48, "space": 49, "grave": 50, "delete": 51, "esc": 53,
        "escape": 53, "return": 36, "enter": 36, "up": 126, "down": 125, "left": 123,
        "right": 124, "home": 115, "end": 119, "pageup": 116, "pagedown": 121, "f1": 122,
        "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97
    ]

    static func virtualKey(for name: String) -> CGKeyCode? {
        table[name]
    }
}
