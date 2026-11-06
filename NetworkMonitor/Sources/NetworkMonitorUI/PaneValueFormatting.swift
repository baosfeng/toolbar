import Foundation

// MARK: - 数值 / 单位分列（纯逻辑，可单测）

/// 把已格式化的数值文本拆成「数值列 + 单位列」两段
///
/// 存在理由：数值单位由设置切换（K/M/B 或 万/亿），同一数值两档宽度不同
/// （`159.59 M` ↔ `1.60 亿`）。视图若为某一档定宽，另一档必然留空或截断；
/// 所以统一拆成两段排版、单位列不参与定宽。
public enum PaneValueFormatting {

    /// 单位片段的分隔方式：分列渲染时数值与单位之间恒留 2pt，不依赖原文空格
    public static let gap: CGFloat = 2

    /// 拆分结果
    public struct Split: Equatable {
        /// 数值部分（含千分位、小数点、正负号）
        public let number: String
        /// 单位部分（如 "M" / "M tok" / "万" / "亿" / "次" / "%"）；无单位时为 ""
        public let unit: String

        public init(number: String, unit: String) {
            self.number = number
            self.unit = unit
        }
    }

    /// 拆分已格式化的数值文本
    ///
    /// 规则（逐条可测）：
    /// 1. 从尾部向前吃「字母 / 中日韩字符 / 空白」，遇到数字、小数点、逗号、百分号即停；
    ///    `%` 视为单位（`95%` → `95` + `%`）；
    /// 2. 单位片段去掉首尾空白；数值片段去掉尾部空白；
    /// 3. 只有数值没有单位时 `unit` 为空串；空文本返回 `("", "")`；
    /// 4. 纯单位文本（如 `—`）不做拆分，整串留在 number 里（占位符要原样显示）。
    public static func split(_ text: String) -> Split {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return Split(number: "", unit: "") }
        var unitChars: [Character] = []
        var seenSymbol = false
        for character in trimmed.reversed() {
            if isUnitCharacter(character) {
                // 单位里允许出现空白（"M tok"），但空白只在已经吃到单位字符之后才算单位
                unitChars.append(character)
                seenSymbol = seenSymbol || character != " "
            } else if character == " " && seenSymbol {
                unitChars.append(character)
            } else {
                break
            }
        }
        let unit = String(String(unitChars.reversed()).trimmingCharacters(in: .whitespaces))
        let number = String(trimmed.dropLast(unitChars.count)).trimmingCharacters(in: .whitespaces)
        guard !unit.isEmpty, !number.isEmpty else { return Split(number: trimmed, unit: "") }
        return Split(number: number, unit: unit)
    }

    /// 该字符是否可作单位的一部分（字母 / 中日韩字符 / 单位符号）
    private static func isUnitCharacter(_ character: Character) -> Bool {
        if character == "%" { return true }
        return character.isLetter
    }
}
