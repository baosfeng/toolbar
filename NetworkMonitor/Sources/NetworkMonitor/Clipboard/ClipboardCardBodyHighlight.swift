import AppKit
import NetworkMonitorDesign
import NetworkMonitorUI

// MARK: - 正文分段高亮（搜索命中叠色）

/// ClipboardCardView 的正文高亮段 —— 只给正文一层底色，文字颜色不变
///
/// 单独成族而不是落进 `ClipboardCardView+…`：同族门禁按类名前缀聚合且只允许变小，
/// 高亮是新领域（搜索命中可视化），落进新文件才不撑大既有族。
///
/// 绘制口径：
/// 1. 区间一律来自 `ClipboardSearchHighlight.displayRanges`（显示文本口径），
///    卡片正文此时用的正是 `ClipboardCardTextStyle.breakable` 的输出，两边同一份串；
/// 2. 底色用主题的 `ThemeRole.selectedFill`（选中态 / 悬停浅底，随主题与深浅切换），
///    叠在文字之下、卡底之上，不改任何字形与文字色；
/// 3. 查询为空、条目非文本、区间为空时整段跳过（不画、不测量）。
extension ClipboardCardView {

    /// 高亮底色：主题 accent 的 14%（不写死色值，深浅色与换主题都跟随）
    static var highlightFill: NSColor {
        ThemeStyle.color(.accent).withAlphaComponent(0.14)
    }

    /// 把命中的显示区间叠成一行行底色（正文块内最多 `maxTextLines` 行，超出不再画）
    func drawBodyHighlight(displayText: String, query: String, block: DrawnTextBlock, in body: CGRect) {
        let ranges = ClipboardSearchHighlight.displayRanges(inDisplay: displayText, query: query)
        guard !ranges.isEmpty else { return }
        // 与 DrawnTextBlock.draw(centeredIn:) 同一份垂直居中口径：先算块高再定位
        let height = block.drawHeight(width: body.width)
        guard height > 0, body.width > 0 else { return }
        let origin = CGPoint(x: body.minX, y: body.minY + max(0, (body.height - height) / 2))
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        // 卡片是 flipped 上下文；文字块本身不翻转，底色用同一套坐标，故这里也不翻
        let highlight = ClipBodyHighlight(fill: Self.highlightFill)
        highlight.draw(ranges: ranges, in: displayText, block: block,
                       origin: origin, width: body.width,
                       maxHeight: min(body.height, height))
        ctx.restoreGState()
    }
}

// MARK: - 区间 → 矩形

/// 命中区间到绘制矩形的换算（与文字同一段落样式量，不另写一套排版）
///
/// `@MainActor`：绘制参数取自 `DrawnTextBlock`（主 actor 隔离），且绘制本身只在主线程发生。
@MainActor
private struct ClipBodyHighlight {

    /// 底色
    let fill: NSColor

    /// 逐行把区间铺成矩形
    ///
    /// 做法：用与 `DrawnTextBlock` 完全相同的段落样式建一份 `NSTextStorage` / `NSLayoutManager`，
    /// 逐区间问「这段字符占哪些行片段」（`enumerateEnclosingRects`），每片段画一块圆角 2pt 的底色。
    /// 之所以不用自算行高，是因为比例字体下行内上下留白与行距都会影响观感，交给排版引擎最稳。
    func draw(ranges: [Range<String.Index>], in displayText: String, block: DrawnTextBlock,
              origin: CGPoint, width: CGFloat, maxHeight: CGFloat) {
        guard !ranges.isEmpty, width > 0, maxHeight > 0 else { return }
        let storage = NSTextStorage(string: displayText, attributes: [
            .font: block.font,
            .paragraphStyle: paragraph(block),
        ])
        let manager = NSLayoutManager()
        storage.addLayoutManager(manager)
        let container = NSTextContainer(size: CGSize(width: width, height: maxHeight))
        container.lineFragmentPadding = 0
        container.maximumNumberOfLines = block.maxLines > 0 ? block.maxLines : 0
        container.lineBreakMode = block.lineBreakMode
        manager.addTextContainer(container)
        // 与 .usesFontLeading 一致：让 NSLayoutManager 也按字体行距排版
        manager.usesFontLeading = true
        manager.ensureLayout(for: container)

        let nsText = displayText as NSString
        for range in ranges {
            let nsRange = NSRange(range, in: displayText)
            // 选区在最末行之后（被 maxLines / maxHeight 截断）：不画，避免溢出正文区
            guard nsRange.length > 0, NSMaxRange(nsRange) <= nsText.length else { continue }
            manager.enumerateEnclosingRects(forGlyphRange: manager.glyphRange(forCharacterRange: nsRange,
                                                                             actualCharacterRange: nil),
                                            withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                                            in: container) { rect, _ in
                guard rect.height > 0, rect.width > 0 else { return }
                let target = CGRect(x: origin.x + rect.minX,
                                    y: origin.y + rect.minY,
                                    width: rect.width,
                                    height: min(rect.height, block.lineHeight))
                guard target.minY + target.height <= origin.y + maxHeight + 0.5 else { return }
                fill.setFill()
                NSBezierPath(roundedRect: target, xRadius: 2, yRadius: 2).fill()
            }
        }
    }

    /// 与 `DrawnTextBlock` 绘制时同参数的段落样式
    private func paragraph(_ block: DrawnTextBlock) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = block.lineBreakMode
        style.lineSpacing = block.lineSpacing
        style.alignment = block.alignment
        return style
    }
}
