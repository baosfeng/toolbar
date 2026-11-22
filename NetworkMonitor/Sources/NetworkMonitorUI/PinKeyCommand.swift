import CoreGraphics
import Foundation

// MARK: - 贴图窗键位解析（纯逻辑，可单测）

/// 贴图窗口按键 → 命令
///
/// Snipaste 的「只对贴图有效」键位表里有几组本项目曾经没有的通路：
/// ⌘W 关闭窗口、`+` / `-` 缩放、`⌃+` / `⌃-` 调透明度、`5` 灰度、`6` 反色。
/// 解析放在纯逻辑里，贴图窗口只负责执行，键盘口径可被 TestRunner 直接断言。
///
/// 键位归属：1…4 旋转镜像、5 灰度、6 反色与官方一致；缩略图不是官方默认键位
/// （官方是 ⇧+左键双击），原先借用 5，本轮 5 让位给灰度后顺延到 7。
public enum PinKeyCommand: Equatable {
    /// 关闭（可恢复）
    case close
    /// 销毁（不可恢复）
    case destroy
    case rotateClockwise
    case rotateCounterClockwise
    case mirrorHorizontal
    case mirrorVertical
    /// 灰度（官方键位 5）
    case grayscale
    /// 反色（官方键位 6）
    case invert
    case thumbnail
    /// 缩放：factor > 1 放大、< 1 缩小
    case zoom(factor: CGFloat)
    /// 透明度增量（负数变透明）
    case alphaDelta(CGFloat)
    /// 重置为 100% 大小与 100% 不透明
    case resetSizeAndAlpha
    /// 复制纯文本（官方 ⌘⇧C，仅当该贴图由文本转换而来）
    case copyPlainText
}

/// 贴图窗键位解析
public enum PinKeyCommandResolver {

    /// 键盘缩放步进（每次 + / - 变化 20%，与滚轮的连续微调互补）
    public static let zoomStep: CGFloat = 1.2
    /// 键盘透明度步进（每次 ⌃+ / ⌃- 变化 0.1，十步走完 0 到 1）
    public static let alphaStep: CGFloat = 0.1

    /// 无字符时的键码兜底（输入法或特殊键盘布局下系统可能不给字符）
    private static let keyCodeLetters: [Int: String] = [
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 13: "w"
    ]

    /// 解析一次按键；返回 nil 表示贴图窗不接管，交回系统
    public static func resolve(keyCode: Int,
                               characters: String?,
                               modifiers: SnipKeyCommandResolver.Modifiers) -> PinKeyCommand? {
        // Esc：官方「关闭贴图」；⇧+Esc 销毁（不可再恢复）
        if keyCode == 53 {
            return modifiers.contains(.shift) ? .destroy : .close
        }
        guard let letter = character(keyCode: keyCode, characters: characters) else { return nil }
        // ⌘W 关闭窗口、⌘⇧C 复制纯文本：官方贴图键位表里明写
        if modifiers.contains(.command) {
            if letter == "w" { return .close }
            if letter == "c", modifiers.contains(.shift) { return .copyPlainText }
            return nil
        }
        // ⌃ 与 + / - 联用是调透明度；不带 ⌃ 才是缩放（官方两张表各占一档）
        if modifiers.contains(.control) {
            switch letter {
            case "+", "=": return .alphaDelta(alphaStep)
            case "-", "_": return .alphaDelta(-alphaStep)
            default: break
            }
        }
        switch letter {
        case "1": return .rotateClockwise
        case "2": return .rotateCounterClockwise
        case "3": return .mirrorHorizontal
        case "4": return .mirrorVertical
        // 官方贴图键位表：5 = 灰度、6 = 反色（见 docs/调研/Snipaste功能清单.md 贴图章节）
        case "5": return .grayscale
        case "6": return .invert
        // 缩略图原本占着 5，官方口径下 5 是灰度；缩略图改由 ⇧⇧ 双击（菜单项仍保留）
        case "7": return .thumbnail
        case "+", "=": return .zoom(factor: zoomStep)
        case "-", "_": return .zoom(factor: 1 / zoomStep)
        default: return nil
        }
    }

    /// 取按键字符：优先用系统解码的字符，缺字符时按主键盘数字键兜底
    private static func character(keyCode: Int, characters: String?) -> String? {
        if let characters, !characters.isEmpty { return characters.lowercased() }
        return keyCodeLetters[keyCode]
    }
}
