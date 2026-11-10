import CoreGraphics
import Foundation

// MARK: - 截图覆盖层键位解析（纯逻辑，可单测）

/// 覆盖层按键 → 命令
///
/// 此前覆盖层的键位判断写在视图的 `switch` 里，裸字母分支排在带 ⌘ 的分支之前，
/// 于是 `case "a"`、`case "s"` 先把按键吃掉：⌘A 全选与 ⌘S 保存从来没触发过
/// （用户按 ⌘S 只看到选区挪了 1 点）。这里把顺序写成显式规则并配上断言，
/// 新增键位时也不会再被前面的裸键遮蔽。
public enum SnipKeyCommand: Equatable {
    case cancel
    case confirm
    /// 切换截图里是否包含鼠标指针
    case toggleCursor
    /// 切换工具条显示
    case toggleToolBar
    case historyOlder
    case historyNewer
    case toggleWindowDetection
    /// 选区微调（dx / dy 为方向，±1）
    case nudge(dx: CGFloat, dy: CGFloat)
    /// 取鼠标所在像素颜色写入剪贴板
    case copyColor
    case selectAll
    case rotateSelectedText
    case restoreLastSelection
    case pin
    case undo
    case redo
    /// 保存选区；quick 为 true 表示快速保存到默认目录
    case save(quick: Bool)
    /// 复制选区到剪贴板
    case copyImage
    case none
}

/// 键位解析
public enum SnipKeyCommandResolver {

    /// 解析用到的修饰键（不引用 AppKit，便于脱离界面单测）
    public struct Modifiers: OptionSet, Equatable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let command = Modifiers(rawValue: 1 << 0)
        public static let shift = Modifiers(rawValue: 1 << 1)
        public static let control = Modifiers(rawValue: 1 << 2)
        public static let option = Modifiers(rawValue: 1 << 3)

        /// 逐键构造（界面层把 AppKit 的修饰键集合翻译成这四个布尔后传进来，便于脱离 AppKit 单测）
        public init(command: Bool = false, shift: Bool = false,
                    control: Bool = false, option: Bool = false) {
            var value: Modifiers = []
            if command { value.insert(.command) }
            if shift { value.insert(.shift) }
            if control { value.insert(.control) }
            if option { value.insert(.option) }
            self = value
        }
    }

    /// 虚拟键码（与 Carbon 一致，只为可读性起名）
    public enum KeyCode {
        public static let escape = 53
        public static let returnKey = 36
        public static let keypadEnter = 76
        public static let backtick = 50
        public static let space = 49
        public static let comma = 43
        public static let period = 47
        public static let tab = 48
        public static let leftArrow = 123
        public static let rightArrow = 124
        public static let downArrow = 125
        public static let upArrow = 126
    }

    /// 解析一次按键
    ///
    /// - Parameters:
    ///   - keyCode: 虚拟键码
    ///   - characters: `charactersIgnoringModifiers`（已忽略修饰键影响）
    ///   - modifiers: 当前修饰键
    public static func resolve(keyCode: Int, characters: String?, modifiers: Modifiers) -> SnipKeyCommand {
        // 带 ⌘ 的组合一律先走字母分支：⌘Tab、⌘空格这些是系统快捷键，
        // 不能因为键码恰好等于覆盖层的「切窗口检测 / 显隐工具条」就被吃掉
        // （早期实现把键码表放在最前面，截图界面里 ⌘Tab 与 ⌘空格直接失效）。
        if modifiers.contains(.command) {
            return resolveCommandLetter(characters: characters, modifiers: modifiers)
        }

        switch keyCode {
        case KeyCode.escape: return .cancel
        case KeyCode.returnKey, KeyCode.keypadEnter: return .confirm
        case KeyCode.backtick: return .toggleCursor
        case KeyCode.space: return .toggleToolBar
        case KeyCode.comma: return .historyOlder
        case KeyCode.period: return .historyNewer
        case KeyCode.tab: return .toggleWindowDetection
        case KeyCode.leftArrow: return .nudge(dx: -1, dy: 0)
        case KeyCode.rightArrow: return .nudge(dx: 1, dy: 0)
        case KeyCode.downArrow: return .nudge(dx: 0, dy: 1)
        case KeyCode.upArrow: return .nudge(dx: 0, dy: -1)
        default: break
        }

        guard let letter = characters?.lowercased(), letter.count == 1 else { return .none }
        switch letter {
        case "a": return .nudge(dx: -1, dy: 0)
        case "d": return .nudge(dx: 1, dy: 0)
        case "w": return .nudge(dx: 0, dy: -1)
        case "s": return .nudge(dx: 0, dy: 1)
        case "c": return .copyColor
        case "r": return .restoreLastSelection
        default: return .none
        }
    }

    /// 带 ⌘ 的组合：字母决定命令，其余键位一律不接管（它们属于系统快捷键通道）
    private static func resolveCommandLetter(characters: String?,
                                             modifiers: Modifiers) -> SnipKeyCommand {
        guard let letter = characters?.lowercased(), letter.count == 1 else { return .none }
        switch letter {
        case "s" where modifiers.contains(.shift): return .save(quick: true)
        case "s": return .save(quick: false)
        case "c": return .copyImage
        case "a": return .selectAll
        case "t": return .pin
        case "z" where modifiers.contains(.shift): return .redo
        case "z": return .undo
        case "r": return .rotateSelectedText
        default: return .none
        }
    }
}
