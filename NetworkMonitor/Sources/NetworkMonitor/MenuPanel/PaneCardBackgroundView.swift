import AppKit
import NetworkMonitorCore

// MARK: - 共用卡片底（六页同一底色 / 圆角 / 玻璃三件套）

/// 卡片底 —— 走主题的玻璃三件套（半透明底 + 顶部高光 + 半透明描边），六页所有卡片都从这里取
///
/// 与 `MenuPanelCardView`（网络页等用的轻量卡）共用同一段绘制（`ThemeStyle.drawCard`），
/// 两处不再各写一套底色与圆角；描边与高光的强度由主题材质配方给，省电档会自动退回
/// 不透明实色（`ThemeStyle.cardFillAlpha == 1`、高光与描边 0）。
/// 用法：作为容器的背景层，内容加在 `contentView` 上（内边距由调用方按令牌层给）。
final class PaneCardBackgroundView: NSView {

    /// 内容容器（已按 `PaneCardStyle.cardPaddingX/Y` 内缩）
    let contentView = NSView()

    /// 底面语义角色 —— 存角色而不是 `NSColor`：换主题 / 换档后重绘即得新色，
    /// 存颜色会在创建瞬间固化（旧实现就踩过这个坑）
    private let fillRole: ThemeRole
    private let radius: CGFloat
    private let paddingX: CGFloat
    private let paddingY: CGFloat

    init(fillRole: ThemeRole = .cardFill,
         radius: CGFloat = PaneCardStyle.cardRadius,
         paddingX: CGFloat = PaneCardStyle.cardPaddingX,
         paddingY: CGFloat = PaneCardStyle.cardPaddingY) {
        self.fillRole = fillRole
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
        ThemeStyle.drawCard(in: bounds, radius: radius, fillRole: fillRole)
        super.draw(dirtyRect)
    }

    /// 外观 / 主题变化后重绘（layer 缓存的是旧颜色，不重绘不会刷新）
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
