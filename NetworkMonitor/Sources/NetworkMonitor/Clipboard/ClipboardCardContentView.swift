import AppKit
import NetworkMonitorCore

// MARK: - 卡片内容层

/// 卡片内容层 — 只画正文 / 占位符号 / meta 行 / 栈角标，不画底色与描边
///
/// 底色、hover 提亮、选中叠色、描边与阴影由 `ClipboardCardBackdropView` 的图层承担；
/// 缩略图真图由卡片主视图的独立图层淡入覆盖，本层只负责占位符号与降级说明。
@MainActor
final class ClipboardCardContentView: NSView {

    /// 当前条目（nil 时整层不绘制）
    var item: ClipboardItem?
    /// 卡片序号（1…9 显示 ⌘N）
    var number: Int?
    /// 选中态（只影响正文色微调，不重画底色）
    var isSelected = false
    /// 缩略图是否已就绪（就绪后不再画占位符号与其说明）
    var thumbnailReady = false

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }

    /// 内容重设（视图池复用：内容变化无条件重绘）
    func update(with item: ClipboardItem, number: Int) {
        self.item = item
        self.number = number
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let item else { return }
        let content = ClipboardCardLayout.contentRect(in: bounds)
        let body = ClipboardCardLayout.bodyRect(in: bounds)
        if item.kind == .image {
            drawImagePlaceholder(item: item, in: body)
        } else {
            drawText(item: item, in: body)
        }
        drawMeta(item: item, in: content)
    }

    /// 文本卡：可断行正文垂直居中，最多 7 行，超出尾部省略
    private func drawText(item: ClipboardItem, in body: NSRect) {
        let monospaced = ClipboardCardTextStyle.isMonospaced(item.preview)
        let font = monospaced
            ? NSFont.monospacedSystemFont(ofSize: ClipboardCardView.monospacedFontSize, weight: .regular)
            : NSFont.systemFont(ofSize: ClipboardCardView.bodyFontSize)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 2
        paragraph.alignment = .left

        let text = item.preview.isEmpty ? "（空内容）" : item.preview
        let attributed = NSAttributedString(
            string: ClipboardCardTextStyle.breakable(text, monospaced: monospaced),
            attributes: [.font: font,
                         .foregroundColor: NSColor.labelColor,
                         .paragraphStyle: paragraph])

        let lineHeight = ceil(font.ascender - font.descender + paragraph.lineSpacing)
        let maxHeight = lineHeight * CGFloat(ClipboardCardView.maxTextLines)
        let measured = attributed.boundingRect(
            with: NSSize(width: body.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]).height
        let drawHeight = min(maxHeight, ceil(measured))
        let rect = NSRect(x: body.minX,
                          y: body.minY + max(0, (body.height - drawHeight) / 2),
                          width: body.width,
                          height: drawHeight)
        attributed.draw(with: rect,
                        options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine])
    }

    /// 图片卡：缩略图未就绪时画占位符号（真图由卡片主视图图层覆盖），原图缺失补一行原因
    private func drawImagePlaceholder(item: ClipboardItem, in body: NSRect) {
        guard body.width > 0, body.height > 0 else { return }
        let path = NSBezierPath(roundedRect: body,
                                xRadius: ClipboardCardView.thumbnailCornerRadius,
                                yRadius: ClipboardCardView.thumbnailCornerRadius)
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        NSColor.underPageBackgroundColor.setFill()
        body.fill()
        let symbolSize: CGFloat = 24
        ClipboardCardView.symbolImage(named: "photo", color: .secondaryLabelColor, pointSize: symbolSize)?
            .draw(in: NSRect(x: body.midX - symbolSize / 2, y: body.midY - symbolSize / 2,
                             width: symbolSize, height: symbolSize))
        // 原图拒绝落盘（像素超限 / 解码失败）时补一行原因，避免用户以为图片丢了
        if item.imagePath == nil, !thumbnailReady {
            drawPlaceholderCaption(item.preview, in: body)
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// 占位降级说明（单行居中、中间截断；空文案不绘制）
    private func drawPlaceholderCaption(_ caption: String, in body: NSRect) {
        let text = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, body.height > 60 else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingMiddle
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph
        ]
        let rect = NSRect(x: body.minX + 6, y: body.midY + 18, width: body.width - 12, height: 14)
        (text as NSString).draw(in: rect, withAttributes: attributes)
    }

    /// 底部单行 meta：左「类型图标 + ⌘N」，右「相对时间 + 来源 App 图标」
    ///
    /// 收藏星是独立子视图（可做弹入动效），不在此绘制。
    private func drawMeta(item: ClipboardItem, in content: NSRect) {
        let rowY = ClipboardCardLayout.metaRowY(in: bounds)
        let metaAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: ClipboardCardView.metaFontSize, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        // 左：类型图标
        var leftX = content.minX
        let typeIcon = ClipboardCardView.typeIconSize
        ClipboardCardView.symbolImage(named: ClipboardCardView.symbolName(for: item),
                                      color: .secondaryLabelColor, pointSize: typeIcon)?
            .draw(in: NSRect(x: leftX, y: rowY + (ClipboardCardView.metaHeight - typeIcon) / 2,
                             width: typeIcon, height: typeIcon))
        leftX += typeIcon + ClipboardCardView.metaGap

        // 左：⌘N 直选提示（只有 1…9 有位）
        if let number, (1...9).contains(number) {
            let label = "⌘\(number)" as NSString
            let size = label.size(withAttributes: metaAttributes)
            label.draw(at: NSPoint(x: leftX, y: rowY + (ClipboardCardView.metaHeight - size.height) / 2),
                       withAttributes: metaAttributes)
        }

        // 右：来源 App 图标（12pt、75% 不透明度，不显示 App 名） + 相对时间
        var rightX = content.maxX
        let appIcon = ClipboardCardView.appIconSize
        if let icon = ClipboardCardView.applicationIcon(bundleID: item.sourceBundleID) {
            icon.draw(in: NSRect(x: rightX - appIcon,
                                 y: rowY + (ClipboardCardView.metaHeight - appIcon) / 2,
                                 width: appIcon, height: appIcon),
                      from: .zero, operation: .sourceOver, fraction: 0.75)
            rightX -= appIcon + ClipboardCardView.metaGap
        }
        let time = ClipboardRelativeTime.string(from: item.createdAt) as NSString
        let timeSize = time.size(withAttributes: metaAttributes)
        time.draw(at: NSPoint(x: rightX - timeSize.width,
                              y: rowY + (ClipboardCardView.metaHeight - timeSize.height) / 2),
                  withAttributes: metaAttributes)
    }

}