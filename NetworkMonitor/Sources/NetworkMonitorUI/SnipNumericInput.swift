import CoreGraphics
import Foundation

// MARK: - 数值输入解析（纯逻辑，可单测）

/// 把用户敲进输入框的字符串解析成一个数值
///
/// 容错口径与 `SnipSizeInput`（选区尺寸）一致：只在数字与分隔符上宽容，不猜语义。
/// 允许的写法：`12` / `12pt` / `12 px` / `60%` / `12.5`。
/// 百分之几会按 0…100 映射到 0…1；带不带单位都可以，单位只作提示。
public enum SnipNumericInput {

    /// 解析一个数值；返回 nil 表示这串没法用（调用方据此保持原值不变，不静默改成 0）
    public static func parse(_ text: String, param: SnipNumericParam) -> CGFloat? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // 透明度优先按百分比理解：用户写 60 时想的是 60%，不是 60 倍
        if param == .opacity {
            let isPercent = trimmed.contains("%")
            guard let raw = firstNumber(in: trimmed) else { return nil }
            let value = isPercent || raw > 1 ? raw / 100 : raw
            return param.clampValue(value)
        }
        guard let raw = firstNumber(in: trimmed) else { return nil }
        return param.clampValue(raw)
    }

    /// 取字符串里的第一个数字（支持负号与小数点）
    ///
    /// 不要求整串都是数字：`12pt` / `12 px` 这类带单位的写法应当能用，
    /// 而"12×13"这种多值输入只取第一个 —— 数值参数本来只有一个值，
    /// 多填的部分不猜，取第一个最接近用户意图。
    public static func firstNumber(in text: String) -> CGFloat? {
        var digits = ""
        var hasDot = false
        var started = false
        for character in text {
            if character.isNumber {
                digits.append(character)
                started = true
            } else if character == "." || character == "·" {
                guard !hasDot else { break }
                hasDot = true
                digits.append(".")
            } else if character == "-" && !started {
                digits.append("-")
            } else if started {
                break
            }
        }
        guard !digits.isEmpty, digits != "-", digits != "." else { return nil }
        return Double(digits).map { CGFloat($0) }
    }
}
