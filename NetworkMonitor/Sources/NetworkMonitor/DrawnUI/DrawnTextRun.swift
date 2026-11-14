import AppKit

// MARK: - 文本绘制（带测量缓存）

/// 文字测量缓存 —— 自绘列表里所有尺寸计算的唯一出口
///
/// 为什么必须缓存：自绘列表每次 `draw` 要排几十上百段文字，而每次
/// `NSAttributedString.size()` 都会走一遍 CoreText（`NSCoreTypesetter` + 字距表），
/// 那是自绘最大的重复开销。尺寸只与「字符串 + 字体 + 宽度上限」有关，与颜色无关。
/// 缓存有界：超过条数上限整体清空（不按 LRU 精细淘汰，换来实现与开销都可控）。
@MainActor
final class DrawnTextMeasurer {

    static let shared = DrawnTextMeasurer()

    private struct WidthKey: Hashable {
        let string: String
        let fontName: String
        let fontSize: CGFloat
        let limit: CGFloat
    }

    private struct HeightKey: Hashable {
        let fontName: String
        let fontSize: CGFloat
    }

    private var widths: [WidthKey: CGFloat] = [:]
    private var heights: [HeightKey: CGFloat] = [:]
    /// 缓存条数上限（超了整体清空）
    private let capacity = 4096

    private init() {}

    /// 单行宽度（受 `limit` 限制；`limit` 一般传行内可用宽度）
    func width(string: String, font: NSFont, limit: CGFloat) -> CGFloat {
        guard !string.isEmpty else { return 0 }
        let key = WidthKey(string: string, fontName: font.fontName, fontSize: font.pointSize, limit: limit)
        if let hit = widths[key] { return hit }
        if widths.count >= capacity { widths.removeAll(keepingCapacity: true) }
        let attributed = NSAttributedString(string: string, attributes: [.font: font])
        let measured = ceil(attributed.size().width)
        let clamped = min(measured, limit)
        widths[key] = clamped
        return clamped
    }

    /// 单行行高（字体行高，缓存后零成本）
    func lineHeight(font: NSFont) -> CGFloat {
        let key = HeightKey(fontName: font.fontName, fontSize: font.pointSize)
        if let hit = heights[key] { return hit }
        if heights.count >= capacity { heights.removeAll(keepingCapacity: true) }
        let h = ceil(font.ascender - font.descender + font.leading)
        heights[key] = h
        return h
    }
}

// MARK: - 一段文字

/// 一段要画的文字：内容 + 字体 + 颜色 + 截断方式
///
/// 自绘组件只持有这个值类型（约几十字节），不再为每段文字建 `NSTextField`。
@MainActor
struct DrawnTextRun {

    var string: String
    var font: NSFont
    var color: NSColor
    /// 超宽时是否截断（false 时按实测宽度溢出绘制，用于不介意压边的场景）
    var truncates: Bool = true

    /// 实测宽度（走缓存）
    func width(limit: CGFloat = .greatestFiniteMagnitude) -> CGFloat {
        DrawnTextMeasurer.shared.width(string: string, font: font, limit: limit)
    }

    /// 实测行高（走缓存）
    var lineHeight: CGFloat { DrawnTextMeasurer.shared.lineHeight(font: font) }

    /// 按基线绘制：`baselineY` 是文字基线（flipped 坐标，向下为正）
    ///
    /// 用于大小字号混排（如额度格的 19pt 数值 + 9.5pt 单位）：两者共用一条基线，
    /// 视觉上才是「95 %」而不是「95 悬空的 %」。
    func draw(baselineAt baselineY: CGFloat, x: CGFloat, width: CGFloat, alignment: NSTextAlignment = .left) {
        guard !string.isEmpty, width > 0 else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = truncates ? .byTruncatingTail : .byClipping
        let attributed = NSAttributedString(string: string, attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ])
        // 行框顶 = 基线 - ascender；AppKit 在行框内按字体度量落基线
        let y = baselineY - font.ascender
        attributed.draw(with: CGRect(x: x, y: y, width: width, height: lineHeight),
                        options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                        context: nil)
    }

    /// 把文字画在 rect 里：垂直居中，水平按 `alignment`
    func draw(in rect: CGRect, alignment: NSTextAlignment = .left) {
        guard !string.isEmpty, rect.width > 0 else { return }
        let available = max(rect.width, 1)
        let h = lineHeight
        let y = rect.midY - h / 2
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = truncates ? .byTruncatingTail : .byClipping
        let attributed = NSAttributedString(string: string, attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ])
        attributed.draw(with: CGRect(x: rect.minX, y: y, width: available, height: h),
                        options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                        context: nil)
    }
}
