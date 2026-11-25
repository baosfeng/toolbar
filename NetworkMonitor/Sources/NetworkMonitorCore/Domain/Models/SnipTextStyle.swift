import CoreGraphics
import Foundation

// MARK: - 文字标注样式

/// 文字标注的字体风格族
///
/// 只列系统里必然存在的几个族：自定义字体文件要随包携带 / 做字体选择器，
/// 对截图标注这种一次性的短文本收益很低。这几族覆盖「默认 / 圆润 / 等宽 / 衬线」四类需求。
public enum SnipTextFamily: String, Equatable, Sendable, CaseIterable {
    case system
    case rounded
    case monospaced
    case serif

    public var displayName: String {
        switch self {
        case .system: return "默认"
        case .rounded: return "圆体"
        case .monospaced: return "等宽"
        case .serif: return "衬线"
        }
    }

    /// 二级面板格子里的单字样本
    ///
    /// 格子只有 38pt 宽，放不下「默认」两个字（会被压成一条）。
    /// 取每族第一个字，并把「默认」写成「系」——「默」单看不像字体名，
    /// 而「系」至少能读出「系统字体」这层意思。
    public var panelInitial: String {
        switch self {
        case .system: return "系"
        case .rounded: return "圆"
        case .monospaced: return "等"
        case .serif: return "衬"
        }
    }
}

/// 文字标注的独立样式
///
/// 背景：字号过去由线宽推导（fontSize = lineWidth * 5），用户想写一行大字必须先把笔调粗，
/// 结果线框跟着变粗 —— 两件事被绑在同一根旋钮上。这里把字号 / 字重 / 字体族独立出来，
/// 线宽只管描边。缺省值仍回落到旧的「线宽推导字号」，保证老标注与老偏好零迁移。
public struct SnipTextStyle: Equatable, Sendable {

    /// 绝对字号（点）。nil = 沿用旧口径「由线宽推导」
    public var fontSize: CGFloat?
    /// 是否加粗
    public var bold: Bool
    /// 字体族
    public var family: SnipTextFamily

    public init(fontSize: CGFloat? = nil, bold: Bool = false, family: SnipTextFamily = .system) {
        self.fontSize = fontSize
        self.bold = bold
        self.family = family
    }

    /// 字号可调范围（与线宽同一量级：太小看不见、太大会撑爆选区）
    public static let fontSizeRange: ClosedRange<CGFloat> = 9...160

    /// 常用字号档（二级面板给快捷键，滚轮 / 快捷键可连续微调）
    public static let fontSizePresets: [CGFloat] = [12, 16, 20, 28, 40, 56]

    /// 把字号夹进合法区间
    public static func clampFontSize(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 20 }
        return min(max(value, fontSizeRange.lowerBound), fontSizeRange.upperBound)
    }

    /// 按档位步进字号：delta 为正放大、为负缩小（滚轮 / 快捷键共用）
    ///
    /// 步长按当前字号的比例给（小字 1pt 一档、大字 4pt 一档），
    /// 否则在大字号上按 1pt 调等于没反应。
    public static func steppedFontSize(from size: CGFloat, by delta: Int) -> CGFloat {
        guard delta != 0 else { return size }
        let step = max((size * 0.1).rounded(), 1)
        return clampFontSize(size + CGFloat(delta) * step)
    }
}
