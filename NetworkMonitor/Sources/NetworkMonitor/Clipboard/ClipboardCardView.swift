import AppKit
import NetworkMonitorCore

// MARK: - 卡片视图

/// 剪贴板卡片 — 176 × 198，圆角 12，内边距 10
///
/// 视觉口径：内容区垂直居中，底部单行 meta（左：类型图标 + ⌘N + 收藏星；右：相对时间 + 来源 App 图标），
/// 选中态为 controlAccentColor 1.5pt 描边 + accent 5% 底色（不缩放、不加阴影）。
/// 仅使用 SF Symbols 与系统语义色，浅色 / 深色自适应，禁止 emoji。
/// 静态资源（符号 / 缩略图 / 来源 App 图标）见 `ClipboardCardView+Resources.swift`。
@MainActor
final class ClipboardCardView: NSView {

    /// 卡片尺寸（设计规格：176 × 198）
    static let cardSize = NSSize(width: 176, height: 198)
    /// 卡片圆角
    static let cornerRadius: CGFloat = 12
    /// 卡片内边距
    static let padding: CGFloat = 10
    /// 正文字号
    static let bodyFontSize: CGFloat = 13
    /// 等宽字号（URL / 命令 / JSON）
    static let monospacedFontSize: CGFloat = 12
    /// meta 字号
    static let metaFontSize: CGFloat = 11
    /// 类型图标尺寸
    static let typeIconSize: CGFloat = 14

    /// meta 行高
    private static let metaHeight: CGFloat = 16
    /// 内容区与 meta 行间距
    private static let bodyGap: CGFloat = 6
    /// 正文最大行数
    private static let maxTextLines = 7
    /// meta 行内元素间距
    private static let metaGap: CGFloat = 6
    /// 来源 App 图标尺寸
    private static let appIconSize: CGFloat = 12
    /// 收藏星尺寸
    private static let starSize: CGFloat = 12

    /// 缩略图缓存（原图按需懒加载，卡片只持有缩略图）
    ///
    /// internal：由 `ClipboardCardView+Resources.swift` 跨文件访问（Swift 扩展不能声明存储属性）。
    static let thumbnailCache = NSCache<NSString, NSImage>()
    /// 来源 App 图标缓存（internal 原因同上）
    static let iconCache = NSCache<NSString, NSImage>()

    /// 点击（选中）回调
    var onClick: ((ClipboardCardView) -> Void)?
    /// 双击（粘贴）回调
    var onDoubleClick: ((ClipboardCardView) -> Void)?
    /// 右键「贴到屏幕」回调
    var onPin: ((ClipboardCardView) -> Void)?

    private(set) var item: ClipboardItem?
    private(set) var isSelected = false
    /// 卡片在匹配列表中的序号（1…9 显示 ⌘N，超出不显示）
    private(set) var shortcutNumber: Int?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }

    /// 配置内容与序号（视图池复用：内容变化必须无条件重绘）
    func configure(with item: ClipboardItem, isSelected: Bool, number: Int) {
        self.item = item
        self.shortcutNumber = number
        self.isSelected = isSelected
        needsDisplay = true
    }

    /// 设置选中态：描边 + 底色重绘（不缩放、不改阴影）
    func setSelected(_ selected: Bool) {
        guard isSelected != selected else { return }
        isSelected = selected
        needsDisplay = true
    }

    // MARK: 鼠标

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onClick?(self)
        if event.clickCount >= 2 { onDoubleClick?(self) }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let pinItem = NSMenuItem(title: "贴到屏幕", action: #selector(menuPinToScreen), keyEquivalent: "")
        pinItem.target = self
        menu.addItem(pinItem)
        return menu
    }

    @objc private func menuPinToScreen() {
        onPin?(self)
    }

    // MARK: 绘制

    override func draw(_ dirtyRect: NSRect) {
        guard let item else { return }
        // 描边内缩半个线宽，避免被视图边界裁掉
        let strokeInset: CGFloat = isSelected ? 0.75 : 0.5
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: strokeInset, dy: strokeInset),
                                xRadius: Self.cornerRadius, yRadius: Self.cornerRadius)
        drawBackground(path)

        let content = bounds.insetBy(dx: Self.padding, dy: Self.padding)
        let body = bodyRect(in: content)
        if item.kind == .image {
            drawThumbnail(item: item, in: body)
        } else {
            drawText(item: item, in: body)
        }

        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        if isSelected {
            NSColor.controlAccentColor.setStroke()
            path.lineWidth = 1.5
        }
        path.stroke()

        drawMeta(item: item, in: content)
        if let position = item.stackPosition { drawStackBadge(position, in: content) }
    }

    /// 卡片底色：选中 = 常规底色 + accent 5% 叠加
    private func drawBackground(_ path: NSBezierPath) {
        NSColor.controlBackgroundColor.withAlphaComponent(isSelected ? 1 : 0.72).setFill()
        path.fill()
        guard isSelected else { return }
        NSColor.controlAccentColor.withAlphaComponent(0.05).setFill()
        path.fill()
    }

    /// 内容区（去掉底部 meta 行）
    private func bodyRect(in content: NSRect) -> NSRect {
        NSRect(x: content.minX, y: content.minY, width: content.width,
               height: max(0, content.height - Self.metaHeight - Self.bodyGap))
    }

    /// 文本卡：可断行正文垂直居中，最多 7 行，超出尾部省略
    private func drawText(item: ClipboardItem, in body: NSRect) {
        let monospaced = ClipboardCardTextStyle.isMonospaced(item.preview)
        let font = monospaced
            ? NSFont.monospacedSystemFont(ofSize: Self.monospacedFontSize, weight: .regular)
            : NSFont.systemFont(ofSize: Self.bodyFontSize)

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
        let maxHeight = lineHeight * CGFloat(Self.maxTextLines)
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

    /// 图片卡：缩略图为主体（圆角 6，等比填充裁剪），取不到图时降级为占位符号
    private func drawThumbnail(item: ClipboardItem, in body: NSRect) {
        guard body.width > 0, body.height > 0 else { return }
        let path = NSBezierPath(roundedRect: body, xRadius: 6, yRadius: 6)
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        NSColor.underPageBackgroundColor.setFill()
        body.fill()
        if let image = Self.thumbnail(for: item) {
            Self.drawAspectFill(image: image, in: body)
        } else {
            Self.symbolImage(named: "photo", color: .secondaryLabelColor, pointSize: 24)?
                .draw(in: NSRect(x: body.midX - 12, y: body.midY - 12, width: 24, height: 24))
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// 底部单行 meta：左「类型图标 + ⌘N + 收藏星」，右「相对时间 + 来源 App 图标」
    ///
    /// 不渲染来源 App 名与复制次数（设计稿口径：元信息降级）。
    private func drawMeta(item: ClipboardItem, in content: NSRect) {
        let rowY = content.maxY - Self.metaHeight
        let metaAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: Self.metaFontSize, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        // 左：类型图标
        var leftX = content.minX
        Self.symbolImage(named: Self.symbolName(for: item), color: .secondaryLabelColor,
                         pointSize: Self.typeIconSize)?
            .draw(in: NSRect(x: leftX, y: rowY + (Self.metaHeight - Self.typeIconSize) / 2,
                             width: Self.typeIconSize, height: Self.typeIconSize))
        leftX += Self.typeIconSize + Self.metaGap

        // 左：⌘N 直选提示（只有 1…9 有位）
        if let number = shortcutNumber, (1...9).contains(number) {
            let label = "⌘\(number)" as NSString
            let size = label.size(withAttributes: metaAttributes)
            label.draw(at: NSPoint(x: leftX, y: rowY + (Self.metaHeight - size.height) / 2),
                       withAttributes: metaAttributes)
            leftX += size.width + Self.metaGap
        }

        // 左：收藏星（未收藏空心、已收藏实心）
        let starName = item.isPinned ? "star.fill" : "star"
        let starColor = item.isPinned ? NSColor.systemYellow : NSColor.secondaryLabelColor
        Self.symbolImage(named: starName, color: starColor, pointSize: Self.starSize)?
            .draw(in: NSRect(x: leftX, y: rowY + (Self.metaHeight - Self.starSize) / 2,
                             width: Self.starSize, height: Self.starSize))

        // 右：来源 App 图标（12pt、75% 不透明度，不显示 App 名） + 相对时间
        var rightX = content.maxX
        if let icon = Self.applicationIcon(bundleID: item.sourceBundleID) {
            icon.draw(in: NSRect(x: rightX - Self.appIconSize,
                                 y: rowY + (Self.metaHeight - Self.appIconSize) / 2,
                                 width: Self.appIconSize, height: Self.appIconSize),
                      from: .zero, operation: .sourceOver, fraction: 0.75)
            rightX -= Self.appIconSize + Self.metaGap
        }
        let time = ClipboardRelativeTime.string(from: item.createdAt) as NSString
        let timeSize = time.size(withAttributes: metaAttributes)
        time.draw(at: NSPoint(x: rightX - timeSize.width, y: rowY + (Self.metaHeight - timeSize.height) / 2),
                  withAttributes: metaAttributes)
    }

    /// Paste Stack 角标（右上角 ①②③，按 stack_position 编号）
    private func drawStackBadge(_ position: Int, in content: NSRect) {
        let badge = Self.badgeText(position) as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                                                         .foregroundColor: NSColor.white]
        let size = badge.size(withAttributes: attributes)
        let rect = NSRect(x: content.maxX - size.width - 8, y: content.minY,
                          width: size.width + 8, height: size.height + 2)
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
        badge.draw(at: NSPoint(x: rect.minX + 4, y: rect.minY + 1), withAttributes: attributes)
    }
}
