import AppKit

// MARK: - 共用卡片底（两页同一底色 / 圆角）

/// 卡片底 —— 实色面 + 统一圆角，两页所有卡片都从这里取
///
/// 与 `MenuPanelCardView`（网络页用的半透明浅底 + 8pt 圆角）区别：
/// 那是「叠加在已有面上的一层灰」，这是「一整块卡片面」，深浅色各有一个实色值。
/// 用法：作为容器的背景层，内容加在 `contentView` 上（内边距由调用方按 §卡片语言给）。
final class PaneCardBackgroundView: NSView {

    /// 内容容器（已按 `PaneCardStyle.cardPaddingX/Y` 内缩）
    let contentView = NSView()

    private let fill: NSColor
    private let radius: CGFloat
    private let paddingX: CGFloat
    private let paddingY: CGFloat

    init(fill: NSColor = PaneCardStyle.cardFill,
         radius: CGFloat = PaneCardStyle.cardRadius,
         paddingX: CGFloat = PaneCardStyle.cardPaddingX,
         paddingY: CGFloat = PaneCardStyle.cardPaddingY) {
        self.fill = fill
        self.radius = radius
        self.paddingX = paddingX
        self.paddingY = paddingY
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: paddingX),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -paddingX),
            contentView.topAnchor.constraint(equalTo: topAnchor, constant: paddingY),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -paddingY),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        fill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        super.draw(dirtyRect)
    }
}
