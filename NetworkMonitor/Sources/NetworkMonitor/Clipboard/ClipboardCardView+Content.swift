import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 卡片内容绘制（卡身 / 图片占位 / 缩略图 / 卡脚 / 星标 / 角标）

/// ClipboardCardView 的内容绘制 —— 与改造前 ClipboardCardContentView / ClipboardCardThumbnailView
/// / NSImageView / ClipboardCardStackBadgeView 各自 draw 的那几段逐字同源，
/// 区别只是现在画在同一张卡的一次 draw 里，没有子视图。
///
/// 位置一律取自 ClipboardCardGeometry（纯函数），字号 / 颜色取自本类型与 ClipboardCardView 的令牌，
/// 不在这里写第二套几何。
extension ClipboardCardView {

    // MARK: 字体

    /// 卡脚来源行字体（等宽数字 9.5pt，与卡头的相对时间同档）
    static var metaFont: NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: footerSourceFontSize, weight: .regular)
    }

    /// 卡脚标题字体（11pt semibold：卡身正文之上、卡头类型名之下）
    static var footerTitleFont: NSFont {
        NSFont.systemFont(ofSize: footerTitleFontSize, weight: .semibold)
    }

    /// 正文字体（12pt 系统字：卡身变矮后 13pt 只能排 5 行，12pt 保住 6 行的信息密度）
    static var bodyFont: NSFont {
        NSFont.systemFont(ofSize: bodyFontSize)
    }

    /// 正文等宽字体（URL / 命令 / JSON，11pt）
    static var monospacedBodyFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: monospacedFontSize, weight: .regular)
    }

    /// 角标字体（11pt semibold）
    static var badgeFont: NSFont {
        NSFont.systemFont(ofSize: 11, weight: .semibold)
    }

    /// 角标文字横向内边距
    static let badgeHorizontalInset: CGFloat = 4
    /// 角标纵向补高
    static let badgeVerticalInset: CGFloat = 2

    // MARK: 实测尺寸（几何与命中共用）

    /// ⌘N 提示的实测宽度（不显示时 0）—— 贴在卡脚来源行右侧
    var shortcutWidth: CGFloat {
        guard let text = ClipboardCardGeometry.shortcutText(number: shortcutNumber) else { return 0 }
        return DrawnTextRun(string: text, font: Self.metaFont, color: PaneCardStyle.tertiaryText)
            .exactSize.width
    }

    /// 栈角标实测尺寸（不在栈内为 .zero）
    var badgeSize: CGSize {
        let position = item?.stackPosition ?? 0
        guard position > 0 else { return .zero }
        let run = DrawnTextRun(string: Self.badgeText(position), font: Self.badgeFont, color: .white)
        return CGSize(width: run.exactSize.width + Self.badgeHorizontalInset * 2,
                      height: run.exactSize.height + Self.badgeVerticalInset)
    }

    // MARK: 卡身正文

    /// 文本卡正文：可断行、从卡身顶部开始排（对齐 Paste 的「白卡身」阅读方向），最多 6 行
    ///
    /// 从「垂直居中」改成「顶部对齐」：三段式卡片里卡身是一块固定高度的纸面，
    /// 居中会让短文本浮在卡片中间、与卡头卡脚脱节；顶部对齐才像「一页内容」。
    func drawTextBody(item: ClipboardItem, in body: CGRect) {
        let monospaced = ClipboardCardTextStyle.isMonospaced(item.preview)
        let text = item.preview.isEmpty ? "（空内容）" : item.preview
        let displayText = ClipboardCardTextStyle.breakable(text, monospaced: monospaced)
        let block = DrawnTextBlock(string: displayText,
                                   font: monospaced ? Self.monospacedBodyFont : Self.bodyFont,
                                   color: PaneCardStyle.primaryText,
                                   lineSpacing: 2,
                                   maxLines: Self.maxTextLines)
        drawBodyHighlight(displayText: displayText, query: highlightQuery, block: block, in: body)
        block.draw(topIn: body)
    }

    /// 图片卡：缩略图未就绪时画占位符号（真图随后覆盖），原图缺失补一行原因
    func drawImageBody(item: ClipboardItem, in body: CGRect) {
        guard body.width > 0, body.height > 0 else { return }
        let path = NSBezierPath(roundedRect: body,
                                xRadius: Self.thumbnailCornerRadius,
                                yRadius: Self.thumbnailCornerRadius)
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        PaneCardStyle.bandFill.setFill()
        body.fill()
        let symbolSize: CGFloat = 22
        DrawnSymbolRun.symbol(named: "photo", color: PaneCardStyle.tertiaryText, pointSize: symbolSize)?
            .draw(in: CGRect(x: body.midX - symbolSize / 2, y: body.midY - symbolSize / 2,
                             width: symbolSize, height: symbolSize))
        // 原图拒绝落盘（像素超限 / 解码失败）时补一行原因，避免用户以为图片丢了；
        // 缩略图已就绪时不再画（会被真图覆盖）
        if item.imagePath == nil, thumbnail == nil {
            drawPlaceholderCaption(item.preview, in: body)
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// 占位降级说明（单行居中、中间截断；空文案不绘制）
    func drawPlaceholderCaption(_ caption: String, in body: CGRect) {
        let text = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, body.height > 60 else { return }
        let block = DrawnTextBlock(string: text,
                                   font: NSFont.systemFont(ofSize: 10),
                                   color: PaneCardStyle.secondaryText,
                                   lineSpacing: 0,
                                   maxLines: 1,
                                   lineBreakMode: .byTruncatingMiddle,
                                   alignment: .center)
        block.draw(topIn: CGRect(x: body.minX + 6, y: body.midY + 16,
                                 width: body.width - 12, height: 14))
    }

    /// 缩略图真图：圆角 6 裁切 + 底填 + 等比填充，就绪后 0.2s 淡入
    func drawThumbnailImage(in body: CGRect) {
        guard let thumbnail else { return }
        let path = NSBezierPath(roundedRect: body,
                                xRadius: Self.thumbnailCornerRadius,
                                yRadius: Self.thumbnailCornerRadius)
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        NSGraphicsContext.current?.cgContext.setAlpha(thumbnailBlend.value)
        PaneCardStyle.bandFill.setFill()
        body.fill()
        Self.drawAspectFill(image: thumbnail, in: body)
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: 收藏星 / 栈角标

    /// 收藏星：始终绘制（star / star.fill），切换收藏态时按弹入曲线缩放
    func drawStar(item: ClipboardItem, in bounds: CGRect) {
        let rect = ClipboardCardGeometry.starRect(in: bounds)
        let image = DrawnSymbolRun.symbol(named: item.isPinned ? "star.fill" : "star",
                                          color: item.isPinned ? .systemYellow : PaneCardStyle.tertiaryText,
                                          pointSize: Self.starSize)
        drawPop(image, in: rect, progress: starPopBlend.value)
    }

    /// 栈角标：accent 胶囊 + 白色编号（①…⑳，20 以上为数字），推进时弹入
    func drawStackBadge(item: ClipboardItem, in bounds: CGRect) {
        let position = item.stackPosition ?? 0
        guard position > 0 else { return }
        var rect = ClipboardCardGeometry.badgeRect(in: bounds, badgeSize: badgeSize)
        let scale = MotionKit.popScale(badgePopBlend.value)
        if abs(scale - 1) > 0.001 {
            let center = CGPoint(x: rect.midX, y: rect.midY)
            rect = CGRect(x: center.x - rect.width * scale / 2,
                          y: center.y - rect.height * scale / 2,
                          width: rect.width * scale, height: rect.height * scale)
        }
        DrawnInk.fill(rect, radius: rect.height / 2, color: .controlAccentColor)
        let run = DrawnTextRun(string: Self.badgeText(position), font: Self.badgeFont, color: .white)
        let textSize = run.exactSize
        run.draw(at: CGPoint(x: rect.minX + (rect.width - textSize.width) / 2,
                             y: rect.minY + (rect.height - textSize.height) / 2))
    }

    /// 按弹入进度缩放绘制一张图（星标用；进度 1 时不加任何变换，保证静止态逐像素不变）
    ///
    /// 等比居中（= 改造前 NSImageView 的 .scaleProportionallyUpOrDown）：
    /// 符号图通常不是正方形（12×11.2 这类），直接拉伸到 12×12 会让字形纵向多出 1px。
    private func drawPop(_ image: NSImage?, in rect: CGRect, progress: CGFloat) {
        guard let image else { return }
        let scale = MotionKit.popScale(progress)
        guard abs(scale - 1) > 0.001 else {
            DrawnSymbolRun.drawNative(image, in: rect)
            return
        }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.translateBy(x: center.x, y: center.y)
        NSGraphicsContext.current?.cgContext.scaleBy(x: scale, y: scale)
        NSGraphicsContext.current?.cgContext.translateBy(x: -center.x, y: -center.y)
        DrawnSymbolRun.drawNative(image, in: rect)
        NSGraphicsContext.restoreGraphicsState()
    }
}