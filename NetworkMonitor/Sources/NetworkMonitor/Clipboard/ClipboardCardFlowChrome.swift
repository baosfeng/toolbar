import AppKit

// MARK: - 卡片流容器与空态（从 ClipboardCardFlowView 拆出，守住单文件体积上限）

/// 卡片流容器 — 翻转坐标系，让内容从顶部开始排布，并统一绘制卡片的 hover / 选中投影
///
/// 为什么阴影画在容器上而不画在卡片里：
/// - 卡片自己的 draw 被 bounds 裁切，画不到卡外；
/// - 卡片自身 backing layer 的阴影在离屏渲染路径（快照取证的 cacheDisplay）里不参与合成；
/// - 在容器（卡片之下）按同一个圆角矩形画阴影，既能溢出卡片，又不增加任何视图。
///
/// internal 而非 private：由拆出的主文件 `ClipboardCardFlowView.swift` 跨文件实例化。
@MainActor
final class ClipboardCardFlowContainer: NSView {

    /// 需要投影的卡片矩形（由卡片流按 hover / 选中态灌入；空 = 不画）
    var shadowRects: [NSRect] = [] {
        didSet {
            guard shadowRects != oldValue else { return }
            needsDisplay = true
        }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard !shadowRects.isEmpty, let ctx = NSGraphicsContext.current?.cgContext else { return }
        for rect in shadowRects {
            drawShadow(around: rect, in: ctx)
        }
    }

    /// 只保留卡片外区域：卡片内由卡片自己画卡底，重复填一次会让卡底变深
    private func drawShadow(around rect: NSRect, in ctx: CGContext) {
        let radius = ClipboardCardView.cornerRadius
        let shape = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
                                 xRadius: radius, yRadius: radius)
        let outside = NSBezierPath(rect: bounds)
        outside.append(shape)
        outside.windingRule = .evenOdd

        ctx.saveGState()
        outside.addClip()
        // 参数与改造前底色视图图层上的 CALayer 阴影同源：radius 6 / opacity 0.12 / 向下 1pt
        // 阴影强度：CALayer 的 shadowOpacity 不受内容 alpha 调制，而 CGContext 阴影会按绘制内容
        // 的 alpha 打折；这里把 alpha 反算回去（0.12 / 0.72），叠加后才与改造前的投影深浅一致。
        let shadowAlpha = CGFloat(ClipboardCardView.shadowOpacity) / ClipboardCardView.backgroundAlpha
        // CGContext 的 blur 是模糊核尺度，CALayer.shadowRadius 是可见扩散半径（约 2 倍关系），
        // 用 shadowRadius × 2 才能复刻改造前的扩散跨度。
        ctx.setShadow(offset: CGSize(width: 0, height: 1),
                      blur: ClipboardCardView.shadowRadius * 2,
                      color: NSColor.black.withAlphaComponent(shadowAlpha).cgColor)
        // 阴影强度随绘制内容的 alpha 调制：用与卡底相同的不透明度，投影深浅与改造前一致
        NSColor.controlBackgroundColor.withAlphaComponent(ClipboardCardView.backgroundAlpha).setFill()
        shape.fill()
        ctx.restoreGState()
    }
}

// MARK: - 空态视图

/// 空态视图 — 居中一句话 + 轻量 SF Symbol 图形（禁止 emoji）
///
/// internal 原因同上。
@MainActor
final class ClipboardEmptyStateView: NSView {

    private let message: String
    private let symbolName = "doc.on.clipboard"
    private let iconSize: CGFloat = 24
    private let iconGap: CGFloat = 10

    init(message: String) {
        self.message = message
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持从 nib 初始化") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let text = message as NSString
        let textSize = text.size(withAttributes: attributes)
        let totalHeight = iconSize + iconGap + textSize.height
        let top = max(0, (bounds.height - totalHeight) / 2)

        let configuration = NSImage.SymbolConfiguration(pointSize: iconSize, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor.tertiaryLabelColor]))
        NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)?
            .draw(in: NSRect(x: bounds.midX - iconSize / 2, y: top, width: iconSize, height: iconSize))
        text.draw(at: NSPoint(x: bounds.midX - textSize.width / 2, y: top + iconSize + iconGap),
                  withAttributes: attributes)
    }
}
