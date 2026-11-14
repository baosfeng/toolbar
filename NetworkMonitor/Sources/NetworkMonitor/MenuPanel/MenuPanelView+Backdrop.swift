import AppKit
import NetworkMonitorCore

// MARK: - 面板底（玻璃 + 不透明基色层）

/// 面板底 —— 三层结构的最下两层，独立成视图便于「结构自证」
///
/// 层次（自下而上）：
/// 1. **玻璃**：macOS 26+ `NSGlassEffectView(.regular)`；< 26 回落
///    `NSVisualEffectView(.underWindowBackground, .behindWindow, .active)`；玻璃关闭时该层不存在
/// 2. **基色层**：`theme.surface` 按 `veilAlpha` 铺满。这一层是**实机打回换来的**：
///    改造前主面板试过 `.popover` 材质，真实 popover 合成下背景被压成中灰，
///    10.5pt 语义文字对比度不足（`MenuPanelView:29-31` 的历史说明）。基色层把底面亮度
///    拉回设计值，玻璃只负责边缘模糊与轻微桌面透出。
///
/// 装饰层：`hitTest` 返回 nil，不吃鼠标（点击仍落到其上的控件与卡片）。
@MainActor
final class MenuPanelBackdropView: NSView {

    /// 基色层不透明度：开玻璃时留 18% 给桌面与模糊，关玻璃时全不透明
    static let glassVeilAlpha: CGFloat = 0.82

    private var glass: NSView?
    private let veil = MenuPanelVeilView()

    override var isFlipped: Bool { true }

    /// 装饰层不吃鼠标
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(veil)
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 按当前主题 / 档位重建玻璃层与基色层（切主题、切档、外观变化时调用）
    func refresh() {
        glass?.removeFromSuperview()
        glass = nil
        if let newGlass = GlassStyle.makePanelGlass(interactive: ThemeStyle.profile.glassInteractive) {
            newGlass.frame = bounds
            newGlass.autoresizingMask = [.width, .height]
            addSubview(newGlass, positioned: .below, relativeTo: veil)
            glass = newGlass
        }
        veil.veilAlpha = ThemeStyle.glassEnabled ? Self.glassVeilAlpha : 1
        veil.frame = bounds
        veil.autoresizingMask = [.width, .height]
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        glass?.frame = bounds
        veil.frame = bounds
    }

    /// 外观切换后重绘基色层
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        veil.needsDisplay = true
    }

    #if DEBUG
    /// 结构自证：玻璃类型 / 圆角 / 基色层 alpha / 玻璃是否在最底层
    func structureForEvidence() -> (glassType: String, cornerRadius: CGFloat,
                                   veilAlpha: CGFloat, glassIsBottom: Bool) {
        let glassType = glass.map { String(describing: type(of: $0)) } ?? "无（降级为纯实色）"
        var radius = glass?.layer?.cornerRadius ?? 0
        if #available(macOS 26.0, *), let glassView = glass as? NSGlassEffectView {
            radius = glassView.cornerRadius
        }
        let bottom = glass.map { subviews.first === $0 } ?? true
        return (glassType, radius, veil.veilAlpha, bottom)
    }
    #endif
}

// MARK: - 基色层

/// 面板基色层 —— `theme.surface` 按指定 alpha 铺满，外观变化时重绘
///
/// 用 `draw` 而不是 `layer.backgroundColor`：后者在创建瞬间把 `CGColor` 固化，
/// 切换外观或主题后不会刷新（旧代码就踩过这个坑）。
@MainActor
final class MenuPanelVeilView: NSView {

    /// 不透明度（1 = 完全不透明，盖住玻璃的桌面透出）
    var veilAlpha: CGFloat = 1 {
        didSet { if veilAlpha != oldValue { needsDisplay = true } }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        ThemeStyle.color(.surface).withAlphaComponent(veilAlpha).setFill()
        bounds.fill()
        super.draw(dirtyRect)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

// MARK: - 面板接线

extension MenuPanelView {

    /// 装面板底（构造期调用一次）
    func installBackdrop() {
        addSubview(backdrop, positioned: .below, relativeTo: nil)
        NSLayoutConstraint.activate([
            backdrop.leadingAnchor.constraint(equalTo: leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: trailingAnchor),
            backdrop.topAnchor.constraint(equalTo: topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    /// 主题 / 档位变化后刷新面板底
    func refreshBackdrop() {
        backdrop.refresh()
        needsDisplay = true
    }

    #if DEBUG
    /// 玻璃 / 基色层结构自证（见 `MenuPanelController.backdropStructureForEvidence`）
    func backdropStructureForEvidence() -> (glassType: String, cornerRadius: CGFloat,
                                           veilAlpha: CGFloat, glassIsBottom: Bool) {
        backdrop.structureForEvidence()
    }
    #endif

    /// 递归重绘整棵子树（切主题后把所有动态色重新解析一遍）
    ///
    /// 走递归而不是每一页各自订阅事件：六页共用一套骨架，重绘入口只该有一个，
    /// 页面各写一遍正是历史上「各页风格不搭」的成因之一。
    func markSubtreeNeedsDisplay() {
        markNeedsDisplay(in: self)
    }

    private func markNeedsDisplay(in view: NSView) {
        view.needsDisplay = true
        for subview in view.subviews { markNeedsDisplay(in: subview) }
    }
}
