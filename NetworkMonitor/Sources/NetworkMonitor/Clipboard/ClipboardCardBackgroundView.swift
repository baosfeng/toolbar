import AppKit

// MARK: - 卡片底色

/// 卡片底色 — 半透明内衬（`controlBackgroundColor` 0.72），只用视图绘制
///
/// 用视图而不是裸图层：视图绘制跟随卡片 frame 与外观切换，浅色 / 深色都不会串色；
/// 选中叠色与 hover 提亮由叠加的 `ClipboardCardHighlightView` 负责，本层只画底色。
/// 阴影挂在本视图的 `CALayer.shadow*` 上（radius 6 / opacity 0.12 / offset (0,-1)），
/// 由卡片按「hover 或选中」开关。
@MainActor
final class ClipboardCardBackgroundView: NSView {

    /// 底色不透明度（设计规格 §3.5 B5：半透明内衬）
    static let fillAlpha: CGFloat = 0.72
    /// 阴影不透明度（只在 hover 与选中时出现）
    static let shadowOpacity: Float = 0.12
    /// 阴影半径
    static let shadowRadius: CGFloat = 6
    /// 阴影纵向偏移
    static let shadowOffset = CGSize(width: 0, height: -1)

    /// 阴影当前是否可见（布局时据此重设 shadowOpacity）
    private var isShadowVisible = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // 阴影挂在自身图层上，必须 layer-backed（父视图已 layer-backed 时也显式声明，便于读代码）
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持从 nib 初始化") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    /// 纯装饰层：鼠标事件穿透到卡片本体
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds,
                                xRadius: ClipboardCardView.cornerRadius,
                                yRadius: ClipboardCardView.cornerRadius)
        NSColor.controlBackgroundColor.withAlphaComponent(Self.fillAlpha).setFill()
        path.fill()
    }

    /// 阴影路径跟随自身 bounds（圆角矩形），避免逐帧按 alpha 通道推算投影形状
    override func layout() {
        super.layout()
        guard let layer else { return }
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowRadius = Self.shadowRadius
        layer.shadowOffset = Self.shadowOffset
        layer.shadowOpacity = isShadowVisible ? Self.shadowOpacity : 0
        layer.shadowPath = CGPath(roundedRect: bounds,
                                  cornerWidth: ClipboardCardView.cornerRadius,
                                  cornerHeight: ClipboardCardView.cornerRadius,
                                  transform: nil)
    }

    /// 阴影开关（卡片在 hover 与选中时置 true，其余时间 0 避免整屏投影噪声）
    func setShadowVisible(_ visible: Bool) {
        isShadowVisible = visible
        wantsLayer = true
        layer?.shadowOpacity = visible ? Self.shadowOpacity : 0
    }
}