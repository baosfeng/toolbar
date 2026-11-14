import AppKit

// MARK: - 卡片状态高亮层

/// 卡片状态高亮 — 一个只负责「叠色 + 描边」的覆盖视图
///
/// 选中与 hover 各用一个实例，切换时只过渡各自的 `alphaValue`（`MotionKit.crossFade(view:)`），
/// 视觉上就是底色与描边的一次 0.12s 交叉溶解，不需要重绘卡片内容，也不会硬切。
/// 用视图而不是裸 `CAShapeLayer`：视图的绘制在本视图坐标系内，随卡片 frame 同步，
/// 不会出现「子层尺寸与视图不一致 / 被内容层遮挡」这类层序问题。
@MainActor
final class ClipboardCardHighlightView: NSView {

    /// 叠色（nil = 不叠色）
    var fillColor: NSColor?
    /// 描边色（nil = 不描边）
    var strokeColor: NSColor?
    /// 描边线宽（1pt 常态、1.5pt 加粗）
    var strokeWidth: CGFloat = 1.5

    init(fill: NSColor?, stroke: NSColor?, width: CGFloat = 1.5) {
        self.fillColor = fill
        self.strokeColor = stroke
        self.strokeWidth = width
        super.init(frame: .zero)
        alphaValue = 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持从 nib 初始化") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    /// 纯装饰层：鼠标事件穿透到卡片本体
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        // 描边内缩半个线宽，避免被视图边界裁掉
        let inset = strokeWidth / 2
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: inset, dy: inset),
                                xRadius: ClipboardCardView.cornerRadius,
                                yRadius: ClipboardCardView.cornerRadius)
        if let fillColor {
            fillColor.setFill()
            path.fill()
        }
        if let strokeColor {
            strokeColor.setStroke()
            path.lineWidth = strokeWidth
            path.stroke()
        }
    }
}
