import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 卡片内容绘制（正文 / 图片占位 / 缩略图 / meta / 星标 / 角标）

/// ClipboardCardView 的内容绘制 —— 与改造前 ClipboardCardContentView / ClipboardCardThumbnailView
/// / NSImageView / ClipboardCardStackBadgeView 各自 draw 的那几段逐字同源，
/// 区别只是现在画在同一张卡的一次 draw 里，没有子视图。
///
/// 位置一律取自 ClipboardCardGeometry（纯函数），字号 / 颜色取自本类型与 ClipboardCardView 的令牌，
/// 不在这里写第二套几何。
extension ClipboardCardView {

    // MARK: 字体

    /// meta 行字体（等宽数字 11pt）
    static var metaFont: NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: metaFontSize, weight: .regular)
    }

    /// 正文字体（13pt 系统字）
    static var bodyFont: NSFont {
        NSFont.systemFont(ofSize: bodyFontSize)
    }

    /// 正文等宽字体（URL / 命令 / JSON，12pt）
    static var monospacedBodyFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: monospacedFontSize, weight: .regular)
    }

    /// 角标字体（11pt semibold）
    static var badgeFont: NSFont {
        NSFont.systemFont(ofSize: 11, weight: .semibold)
    }

    /// 角标文字横向内边距（改造前 ClipboardCardStackBadgeView.horizontalInset）
    static let badgeHorizontalInset: CGFloat = 4
    /// 角标纵向补高（改造前 intrinsicContentSize 的 +2）
    static let badgeVerticalInset: CGFloat = 2

    // MARK: 实测尺寸（几何与命中共用）

    /// ⌘N 提示的实测宽度（不显示时 0）
    var shortcutWidth: CGFloat {
        guard let text = ClipboardCardGeometry.shortcutText(number: shortcutNumber) else { return 0 }
        return DrawnTextRun(string: text, font: Self.metaFont, color: .secondaryLabelColor)
            .exactSize.width
    }

    /// 栈角标实测尺寸（不在栈内为 .zero）—— 与改造前 intrinsicContentSize 同口径
    var badgeSize: CGSize {
        let position = item?.stackPosition ?? 0
        guard position > 0 else { return .zero }
        let run = DrawnTextRun(string: Self.badgeText(position), font: Self.badgeFont, color: .white)
        return CGSize(width: run.exactSize.width + Self.badgeHorizontalInset * 2,
                      height: run.exactSize.height + Self.badgeVerticalInset)
    }

    // MARK: 正文

    /// 文本卡正文：可断行、垂直居中、最多 7 行（超出尾部省略）
    func drawTextBody(item: ClipboardItem, in body: CGRect) {
        let monospaced = ClipboardCardTextStyle.isMonospaced(item.preview)
        let text = item.preview.isEmpty ? "（空内容）" : item.preview
        let block = DrawnTextBlock(string: ClipboardCardTextStyle.breakable(text, monospaced: monospaced),
                                   font: monospaced ? Self.monospacedBodyFont : Self.bodyFont,
                                   color: .labelColor,
                                   lineSpacing: 2,
                                   maxLines: Self.maxTextLines)
        block.draw(centeredIn: body)
    }

    /// 图片卡：缩略图未就绪时画占位符号（真图随后覆盖），原图缺失补一行原因
    func drawImageBody(item: ClipboardItem, in body: CGRect) {
        guard body.width > 0, body.height > 0 else { return }
        let path = NSBezierPath(roundedRect: body,
                                xRadius: Self.thumbnailCornerRadius,
                                yRadius: Self.thumbnailCornerRadius)
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        NSColor.underPageBackgroundColor.setFill()
        body.fill()
        let symbolSize: CGFloat = 24
        DrawnSymbolRun.symbol(named: "photo", color: .secondaryLabelColor, pointSize: symbolSize)?
            .draw(in: CGRect(x: body.midX - symbolSize / 2, y: body.midY - symbolSize / 2,
                             width: symbolSize, height: symbolSize))
        // 原图拒绝落盘（像素超限 / 解码失败）时补一行原因，避免用户以为图片丢了；
        // 缩略图已就绪时不再画（会被真图覆盖，与改造前 thumbnailReady 的判据一致）
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
                                   color: .secondaryLabelColor,
                                   lineSpacing: 0,
                                   maxLines: 1,
                                   lineBreakMode: .byTruncatingMiddle,
                                   alignment: .center)
        block.draw(topIn: CGRect(x: body.minX + 6, y: body.midY + 18,
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
        NSColor.underPageBackgroundColor.setFill()
        body.fill()
        Self.drawAspectFill(image: thumbnail, in: body)
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: meta

    /// 底部单行 meta：左「类型图标 + ⌘N + 收藏星」，右「相对时间 + 来源 App 图标」
    ///
    /// 改造前收藏星是独立子视图（可单独弹入），现在改成一次绘制 + 缩放进度，
    /// 位置与层序不变：星标压在 meta 文字之上（原 starView 在 contentView 之后加入）。
    ///
    /// 位图（来源 App 图标）要局部翻正：卡片是 flipped 视图，绘制位图不会自动翻。
    /// 色块与文字不需要——文字由 CoreText 在 flipped 上下文里自行翻正。
    func drawMeta(item: ClipboardItem, in bounds: CGRect) {
        let content = ClipboardCardGeometry.contentRect(in: bounds)
        let rowY = ClipboardCardGeometry.metaRowY(in: bounds)
        let font = Self.metaFont
        let color = NSColor.secondaryLabelColor

        // 左：类型图标
        var leftX = content.minX
        let typeIcon = Self.typeIconSize
        DrawnSymbolRun.symbol(named: Self.symbolName(for: item),
                              color: .secondaryLabelColor,
                              pointSize: typeIcon)?
            .draw(in: CGRect(x: leftX,
                             y: rowY + (Self.metaHeight - typeIcon) / 2,
                             width: typeIcon, height: typeIcon))
        leftX += typeIcon + Self.metaGap

        // 左：⌘N 直选提示（只有 1…9 有位）
        if let text = ClipboardCardGeometry.shortcutText(number: shortcutNumber) {
            let run = DrawnTextRun(string: text, font: font, color: color)
            run.draw(at: CGPoint(x: leftX,
                                 y: rowY + (Self.metaHeight - run.exactSize.height) / 2))
        }

        // 右：来源 App 图标（12pt、75% 不透明度）+ 相对时间
        var rightX = content.maxX
        let appIcon = Self.appIconSize
        if let icon = Self.applicationIcon(bundleID: item.sourceBundleID) {
            // 与缩略图同一条翻正路径：卡片是 flipped 视图，位图绘制不翻正会上下颠倒
            let iconRect = CGRect(x: rightX - appIcon,
                                  y: rowY + (Self.metaHeight - appIcon) / 2,
                                  width: appIcon, height: appIcon)
            DrawnInk.withUnflippedIfNeeded(around: iconRect) {
                icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 0.75)
            }
            rightX -= appIcon + Self.metaGap
        }
        let time = DrawnTextRun(string: ClipboardRelativeTime.string(from: item.createdAt, now: SnapshotClock.now),
                                font: font, color: color)
        time.draw(at: CGPoint(x: rightX - time.exactSize.width,
                              y: rowY + (Self.metaHeight - time.exactSize.height) / 2))
    }

    // MARK: 收藏星 / 栈角标

    /// 收藏星：始终绘制（star / star.fill），切换收藏态时按弹入曲线缩放
    func drawStar(item: ClipboardItem, in bounds: CGRect) {
        let rect = ClipboardCardGeometry.starRect(in: bounds, shortcutWidth: shortcutWidth)
        let image = DrawnSymbolRun.symbol(named: item.isPinned ? "star.fill" : "star",
                                          color: item.isPinned ? .systemYellow : .secondaryLabelColor,
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
