import AppKit

// MARK: - 多行文本块

/// 多行文本块 —— 一段可以断行、可以被行数封顶、尾部省略的文字
///
/// 与 `DrawnTextRun` 的分工：单行读数用 `DrawnTextRun`（0.5pt 网格对齐、基线绘制），
/// 多行正文用本类型（换行测量 + 最多 N 行 + 垂直居中）。
///
/// 绘制参数与改造前的 `ClipboardCardContentView` 完全一致：
/// `.byWordWrapping` + `lineSpacing` + `usesLineFragmentOrigin` + `truncatesLastVisibleLine`，
/// 因此自绘正文与原生标签逐像素同源，只有测量走了 `DrawnTextMeasurer` 缓存。
@MainActor
package struct DrawnTextBlock {

    /// 文字内容
    var string: String
    /// 字体
    package var font: NSFont
    /// 文字颜色
    var color: NSColor
    /// 行距
    package var lineSpacing: CGFloat = 2
    /// 最多绘制行数（超出行数尾部省略；0 表示不限）
    package var maxLines: Int = 0
    /// 断行方式（正文用 .byWordWrapping，单行降级说明用 .byTruncatingMiddle）
    package var lineBreakMode: NSLineBreakMode = .byWordWrapping
    /// 对齐方式
    package var alignment: NSTextAlignment = .left

    package init(string: String,
                font: NSFont,
                color: NSColor,
                lineSpacing: CGFloat = 2,
                maxLines: Int = 0,
                lineBreakMode: NSLineBreakMode = .byWordWrapping,
                alignment: NSTextAlignment = .left) {
        self.string = string
        self.font = font
        self.color = color
        self.lineSpacing = lineSpacing
        self.maxLines = maxLines
        self.lineBreakMode = lineBreakMode
        self.alignment = alignment
    }

    /// 行高（与绘制同源：字体行高 + 行距，向上取整）
    package var lineHeight: CGFloat {
        ceil(font.ascender - font.descender + lineSpacing)
    }

    /// 换行后的自然高度（未按 `maxLines` 封顶；走测量缓存）
    package func measuredHeight(width: CGFloat) -> CGFloat {
        guard !string.isEmpty, width > 0 else { return 0 }
        return DrawnTextMeasurer.shared.blockHeight(string: string, font: font,
                                                    width: width, lineSpacing: lineSpacing)
    }

    /// 实际绘制高度（行数封顶后的整数高度）
    package func drawHeight(width: CGFloat) -> CGFloat {
        let measured = measuredHeight(width: width)
        guard measured > 0 else { return 0 }
        guard maxLines > 0 else { return ceil(measured) }
        return min(lineHeight * CGFloat(maxLines), ceil(measured))
    }

    /// 垂直居中画进 rect：内容按自然高度居中，超过 `maxLines` 时尾部省略
    func draw(centeredIn rect: CGRect) {
        let height = drawHeight(width: rect.width)
        guard height > 0, rect.width > 0 else { return }
        let target = CGRect(x: rect.minX,
                            y: rect.minY + max(0, (rect.height - height) / 2),
                            width: rect.width,
                            height: height)
        draw(topIn: target)
    }

    /// 顶对齐画进给定 rect（单行降级说明这类「位置已定」的文字用）
    package func draw(topIn rect: CGRect) {
        guard !string.isEmpty, rect.width > 0, rect.height > 0 else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = lineBreakMode
        paragraph.lineSpacing = lineSpacing
        paragraph.alignment = alignment
        let attributed = NSAttributedString(string: string, attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ])
        attributed.draw(with: rect,
                        options: [.usesLineFragmentOrigin, .usesFontLeading,
                                  .truncatesLastVisibleLine],
                        context: nil)
    }
}
