import AppKit
import NetworkMonitorCore

// MARK: - 卡片视图

/// 剪贴板卡片 — 168 × 190，选中态 controlAccentColor 2pt 描边 + 缩放 1.02 + 阴影
///
/// 仅使用 SF Symbols 与系统语义色，浅色 / 深色自适应，禁止 emoji。
@MainActor
final class ClipboardCardView: NSView {

    /// 卡片尺寸（设计规格第 9 节）
    static let cardSize = NSSize(width: 168, height: 190)
    /// 卡片圆角
    private static let cornerRadius: CGFloat = 12

    /// 点击（选中）回调
    var onClick: ((ClipboardCardView) -> Void)?
    /// 双击（粘贴）回调
    var onDoubleClick: ((ClipboardCardView) -> Void)?

    private(set) var item: ClipboardItem?
    private(set) var isSelected = false

    /// 缩略图缓存（原图按需懒加载，卡片只持有缩略图）
    private static let thumbnailCache = NSCache<NSString, NSImage>()
    /// 来源 App 图标缓存
    private static let iconCache = NSCache<NSString, NSImage>()

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = Self.cornerRadius
        layer?.masksToBounds = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持从 nib 初始化") }

    /// 配置内容
    func configure(with item: ClipboardItem, isSelected: Bool) {
        self.item = item
        setSelected(isSelected, animated: false)
        needsDisplay = true
    }

    /// 设置选中态：描边 + 缩放 1.02 + 阴影
    func setSelected(_ selected: Bool, animated: Bool) {
        guard isSelected != selected || !animated else { return }
        isSelected = selected
        let transform = selected ? CATransform3DMakeScale(1.02, 1.02, 1) : CATransform3DIdentity
        let apply = {
            self.layer?.transform = transform
            self.layer?.shadowColor = NSColor.black.cgColor
            self.layer?.shadowOpacity = selected ? 0.28 : 0
            self.layer?.shadowRadius = selected ? 6 : 0
            self.layer?.shadowOffset = CGSize(width: 0, height: -2)
        }
        if animated {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.12)
            apply()
            CATransaction.commit()
        } else {
            apply()
        }
        needsDisplay = true
    }

    // MARK: 鼠标

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onClick?(self)
        if event.clickCount >= 2 { onDoubleClick?(self) }
    }

    // MARK: 绘制

    override func draw(_ dirtyRect: NSRect) {
        guard let item else { return }
        let bounds = self.bounds.insetBy(dx: 2, dy: 2)
        let path = NSBezierPath(roundedRect: bounds, xRadius: Self.cornerRadius, yRadius: Self.cornerRadius)

        if item.kind == .image {
            drawImageCard(item: item, in: bounds, path: path)
        } else {
            (isSelected ? NSColor.controlBackgroundColor : NSColor.controlBackgroundColor.withAlphaComponent(0.72)).setFill()
            path.fill()
            drawTextCard(item: item, in: bounds)
        }

        // 选中态：controlAccentColor 2pt 描边
        if isSelected {
            NSColor.controlAccentColor.setStroke()
            path.lineWidth = 2
        } else {
            NSColor.separatorColor.setStroke()
            path.lineWidth = 1
        }
        path.stroke()

        if let position = item.stackPosition { drawStackBadge(position, in: bounds) }
    }

    /// 文本卡：类型符号 + 收藏星 + 4 行摘要 + 底部来源/时间/次数
    private func drawTextCard(item: ClipboardItem, in bounds: NSRect) {
        Self.symbolImage(named: Self.symbolName(for: item.kind), color: .secondaryLabelColor)?
            .draw(in: NSRect(x: 12, y: 12, width: 14, height: 14))
        if item.isPinned {
            Self.symbolImage(named: "star.fill", color: .systemYellow)?
                .draw(in: NSRect(x: bounds.width - 26, y: 11, width: 14, height: 14))
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.lineSpacing = 2
        let text = (item.preview.isEmpty ? "（空内容）" : item.preview) as NSString
        text.draw(with: NSRect(x: 12, y: 36, width: bounds.width - 24, height: 76),
                  options: [.usesLineFragmentOrigin, .usesFontLeading],
                  attributes: [.font: NSFont.systemFont(ofSize: 13),
                               .foregroundColor: NSColor.labelColor,
                               .paragraphStyle: paragraph])

        drawFooter(item: item, in: bounds)
    }

    /// 图片卡：缩略图铺满 + 底部渐变遮罩上叠尺寸与时间
    private func drawImageCard(item: ClipboardItem, in bounds: NSRect, path: NSBezierPath) {
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        NSColor.underPageBackgroundColor.setFill()
        bounds.fill()
        if let image = Self.thumbnail(for: item) {
            Self.drawAspectFill(image: image, in: bounds)
        } else {
            Self.symbolImage(named: "photo", color: .secondaryLabelColor)?
                .draw(in: NSRect(x: bounds.midX - 12, y: bounds.midY - 12, width: 24, height: 24))
        }
        if let gradient = NSGradient(colors: [NSColor.black.withAlphaComponent(0), NSColor.black.withAlphaComponent(0.65)]) {
            gradient.draw(in: NSRect(x: bounds.minX, y: bounds.maxY - 54, width: bounds.width, height: 54), angle: -90)
        }
        let overlay: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11),
                                                      .foregroundColor: NSColor.white]
        let size = "\(item.imageWidth ?? 0)×\(item.imageHeight ?? 0)" as NSString
        size.draw(at: NSPoint(x: 12, y: bounds.maxY - 20), withAttributes: overlay)
        let time = ClipboardRelativeTime.string(from: item.createdAt) as NSString
        let timeSize = time.size(withAttributes: overlay)
        time.draw(at: NSPoint(x: bounds.maxX - 12 - timeSize.width, y: bounds.maxY - 20), withAttributes: overlay)
        NSGraphicsContext.restoreGraphicsState()
    }

    /// 底部行：来源 App 图标 + 相对时间 + ×N 复制次数
    private func drawFooter(item: ClipboardItem, in bounds: NSRect) {
        let y = bounds.height - 34
        var x: CGFloat = 12
        if let icon = Self.applicationIcon(bundleID: item.sourceBundleID) {
            icon.draw(in: NSRect(x: x, y: y + 1, width: 14, height: 14))
            x += 18
        }
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11),
                                                         .foregroundColor: NSColor.secondaryLabelColor]
        let time = ClipboardRelativeTime.string(from: item.createdAt) as NSString
        time.draw(at: NSPoint(x: x, y: y), withAttributes: attributes)
        if item.copyCount > 1 {
            let count = "×\(item.copyCount)" as NSString
            let size = count.size(withAttributes: attributes)
            count.draw(at: NSPoint(x: bounds.maxX - 12 - size.width, y: y), withAttributes: attributes)
        }
    }

    /// Paste Stack 角标（右上角 ①②③，按 stack_position 编号）
    private func drawStackBadge(_ position: Int, in bounds: NSRect) {
        let badge = Self.badgeText(position) as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                                                         .foregroundColor: NSColor.white]
        let size = badge.size(withAttributes: attributes)
        let rect = NSRect(x: bounds.maxX - size.width - 14, y: 8, width: size.width + 8, height: size.height + 3)
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
        badge.draw(at: NSPoint(x: rect.minX + 4, y: rect.minY + 1), withAttributes: attributes)
    }

    // MARK: 静态资源

    /// 类型符号名
    private static func symbolName(for kind: ClipboardItemKind) -> String {
        switch kind {
        case .text: return "text.alignleft"
        case .image: return "photo"
        case .file: return "doc"
        case .rtf: return "textformat"
        }
    }

    /// SF Symbol 着色图（禁止 emoji，全部使用系统符号）
    private static func symbolImage(named name: String, color: NSColor) -> NSImage? {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        return image.withSymbolConfiguration(configuration) ?? image
    }

    /// 缩略图（懒加载 + 缓存）
    private static func thumbnail(for item: ClipboardItem) -> NSImage? {
        let key = item.contentHash as NSString
        if let cached = thumbnailCache.object(forKey: key) { return cached }
        let path = ClipboardImageStore.thumbnailURL(for: item.contentHash).path
        guard let image = NSImage(contentsOfFile: path) ?? item.imagePath.flatMap({ NSImage(contentsOfFile: $0) }) else {
            return nil
        }
        thumbnailCache.setObject(image, forKey: key)
        return image
    }

    /// 来源 App 图标（缓存；取不到时返回 nil，由调用方降级为纯文字）
    private static func applicationIcon(bundleID: String?) -> NSImage? {
        guard let bundleID, !bundleID.isEmpty else { return nil }
        let key = bundleID as NSString
        if let cached = iconCache.object(forKey: key) { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        guard let icon = NSImage(contentsOf: url.appendingPathComponent("Contents/Resources/app.icns"))
                ?? NSWorkspace.shared.icon(forFile: url.path) as NSImage? else { return nil }
        icon.size = NSSize(width: 14, height: 14)
        iconCache.setObject(icon, forKey: key)
        return icon
    }

    /// 等比填充绘制（铺满卡片，超出部分裁剪）
    private static func drawAspectFill(image: NSImage, in rect: NSRect) {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return }
        let scale = max(rect.width / imageSize.width, rect.height / imageSize.height)
        let drawnSize = NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let target = NSRect(x: rect.midX - drawnSize.width / 2,
                            y: rect.midY - drawnSize.height / 2,
                            width: drawnSize.width,
                            height: drawnSize.height)
        image.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1)
    }

    /// 角标文案：1→①，20 以上回退为数字
    static func badgeText(_ position: Int) -> String {
        let circled = "①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯⑰⑱⑲⑳"
        guard position >= 1, position <= circled.count else { return "\(position)" }
        return String(Array(circled)[position - 1])
    }
}
