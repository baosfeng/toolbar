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
    private var layoutWidths: [WidthKey: CGFloat] = [:]
    private var labelHeights: [HeightKey: CGFloat] = [:]
    private var exactSizes: [WidthKey: CGSize] = [:]
    private var blockHeights: [BlockKey: CGFloat] = [:]
    /// 精确尺寸的键（limit = -1 表示「不截断、不取整」）

    /// 多行块测量的键（宽度上限 + 行距都影响换行结果）
    private struct BlockKey: Hashable {
        let string: String
        let fontName: String
        let fontSize: CGFloat
        let width: CGFloat
        let lineSpacing: CGFloat
    }
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

    /// 排版宽度 —— 按 0.5pt 网格向上取整
    ///
    /// AppKit 的标签对齐矩形宽就是「文本宽」，而文本宽落在半像素网格上
    /// （实测 15 种常见字串全部吻合：CPU→24.5、8P · 2E→36.5、11.2 GB / 16.0 GB→88.5）。
    /// 排版必须用这个值而不是取整到整数的 width：差 0.5pt 会让整行元素漂半个像素。
    func layoutWidth(string: String, font: NSFont) -> CGFloat {
        guard !string.isEmpty else { return 0 }
        let key = WidthKey(string: string, fontName: font.fontName,
                           fontSize: font.pointSize, limit: 0)
        if let hit = layoutWidths[key] { return hit }
        if layoutWidths.count >= capacity { layoutWidths.removeAll(keepingCapacity: true) }
        let measured = NSAttributedString(string: string, attributes: [.font: font]).size().width
        let half = ceil(measured * 2) / 2
        layoutWidths[key] = half
        return half
    }

    /// 多行换行后的自然高度（未按行数封顶）
    ///
    /// 与 `NSAttributedString.boundingRect(with:options:)` 同源同参数，因此自绘正文的
    /// 「最多 N 行 / 尾部省略」判定与改造前的标签绘制完全一致，只差这一次 CoreText 排版。
    func blockHeight(string: String, font: NSFont, width: CGFloat, lineSpacing: CGFloat) -> CGFloat {
        guard !string.isEmpty, width > 0 else { return 0 }
        let key = BlockKey(string: string, fontName: font.fontName, fontSize: font.pointSize,
                           width: width, lineSpacing: lineSpacing)
        if let hit = blockHeights[key] { return hit }
        if blockHeights.count >= capacity { blockHeights.removeAll(keepingCapacity: true) }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = lineSpacing
        paragraph.alignment = .left
        let attributed = NSAttributedString(string: string, attributes: [
            .font: font,
            .paragraphStyle: paragraph,
        ])
        let measured = attributed.boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]).height
        blockHeights[key] = measured
        return measured
    }

    /// 精确测量（与 `NSString.size(withAttributes:)` 同源，不取整）
    ///
    /// 单行 meta 文字（类型提示 / 相对时间）在改造前用 `size(withAttributes:)` 定位，
    /// 这里缓存同一份数值：取整到 0.5pt 网格的 `layoutWidth` 会让文字漂半个像素。
    func exactSize(string: String, font: NSFont) -> CGSize {
        guard !string.isEmpty else { return .zero }
        let key = WidthKey(string: string, fontName: font.fontName, fontSize: font.pointSize, limit: -1)
        if let hit = exactSizes[key] { return hit }
        if exactSizes.count >= capacity { exactSizes.removeAll(keepingCapacity: true) }
        let measured = NSAttributedString(string: string, attributes: [.font: font]).size()
        exactSizes[key] = measured
        return measured
    }

    /// 行框高度 —— 与 AppKit 标签的 frame 高一致（按字体整像素取整，不是 CoreText 行高）
    ///
    /// 实测 11pt 粗体 = 14（而 ascender−descender 只有 12.95）、10.5pt 粗体 = 13，
    /// 因此不能自己用 ascender 推，直接按同一个字体量一次并缓存。
    func labelHeight(font: NSFont) -> CGFloat {
        let key = HeightKey(fontName: font.fontName, fontSize: font.pointSize)
        if let hit = labelHeights[key] { return hit }
        if labelHeights.count >= capacity { labelHeights.removeAll(keepingCapacity: true) }
        let h = ceil(NSAttributedString(string: "0", attributes: [.font: font]).size().height)
        labelHeights[key] = h
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

    /// 排版宽度（0.5pt 网格）—— 相邻两件的距离按它算才不漂半个像素（与 AppKit 标签同源）
    var layoutWidth: CGFloat { DrawnTextMeasurer.shared.layoutWidth(string: string, font: font) }

    /// 行框高度（= AppKit 标签的 frame 高）
    var labelHeight: CGFloat { DrawnTextMeasurer.shared.labelHeight(font: font) }

    /// 精确尺寸（与 `NSString.size(withAttributes:)` 同源，不取整）
    var exactSize: CGSize { DrawnTextMeasurer.shared.exactSize(string: string, font: font) }

    /// 按「左上角」绘制 —— 与 `NSString.draw(at:withAttributes:)` 同一段 API，
    /// 用于改造前用点坐标定位的单行文字（meta 行里的 ⌘N / 时间），逐像素不变。
    func draw(at point: CGPoint) {
        guard !string.isEmpty else { return }
        NSAttributedString(string: string, attributes: [
            .font: font,
            .foregroundColor: color,
        ]).draw(at: point)
    }

    /// 顶部对齐绘制：AppKit 的标签把行框贴在 frame 顶部（不是垂直居中）
    ///
    /// 与 draw(in:) 的区别只在 y 的取法：这里直接用 rect.minY，
    /// 因此调用方按「标签 frame」摆好 rect 就能逐像素对上原生标签。
    func draw(topIn rect: CGRect, alignment: NSTextAlignment = .left) {
        guard !string.isEmpty, rect.width > 0 else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = truncates ? .byTruncatingTail : .byClipping
        let attributed = NSAttributedString(string: string, attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ])
        attributed.draw(with: CGRect(x: rect.minX, y: rect.minY,
                                     width: rect.width, height: max(rect.height, labelHeight)),
                        options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                        context: nil)
    }

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
