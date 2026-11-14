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

    /// 卡片投影参数（与改造前底色视图图层上的 CALayer 阴影同源：radius 6 / opacity 0.12 / 向下 1pt）
    ///
    /// 换算口径在 `DrawnCardShadow` 里：CGContext 的 blur 是模糊核尺度（= shadowRadius × 2 才等于可见扩散跨度）、
    /// 阴影强度会按绘制内容 alpha 打折（opacity ÷ backgroundAlpha 反算回等效值）。
    private var cardShadow: DrawnCardShadow {
        DrawnCardShadow(radius: ClipboardCardView.cornerRadius,
                        opacity: CGFloat(ClipboardCardView.shadowOpacity),
                        contentAlpha: ClipboardCardView.backgroundAlpha,
                        blur: ClipboardCardView.shadowRadius * 2,
                        offset: CGSize(width: 0, height: 1),
                        fillColor: .controlBackgroundColor)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !shadowRects.isEmpty, let ctx = NSGraphicsContext.current?.cgContext else { return }
        let shadow = cardShadow
        for rect in shadowRects {
            shadow.draw(around: rect, in: ctx, clippingTo: bounds)
        }
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

        DrawnSymbolRun.symbol(named: symbolName, color: .tertiaryLabelColor, pointSize: iconSize)?
            .draw(in: NSRect(x: bounds.midX - iconSize / 2, y: top, width: iconSize, height: iconSize))
        text.draw(at: NSPoint(x: bounds.midX - textSize.width / 2, y: top + iconSize + iconGap),
                  withAttributes: attributes)
    }
}
