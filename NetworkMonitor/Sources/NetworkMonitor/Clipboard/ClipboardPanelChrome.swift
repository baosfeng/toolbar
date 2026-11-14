import AppKit

// MARK: - 面板两级材质与发丝分隔线
//
// 面板底是控制器建的 `.hudWindow`（圆角 14pt）外层；里层内衬与发丝分隔线挂在面板内容视图上，
// 层次因此固定为「`.hudWindow` 底 → 内衬 → 发丝分隔线 → 控件与卡片 → 浮层」。里层放内容视图而非
// 控制器，是为了让离屏快照画布（复用 `ClipboardPanelView`）取证到与真机同一套层次。

// MARK: - 内衬（两级材料的里层）

/// 面板内衬 — `.underWindowBackground` 材质、圆角 12pt、相对面板边界内缩 1pt
///
/// 与外层 `.hudWindow`（圆角 14pt）形成「面板 → 内容」两级材质：内缩 1pt + 圆角小 2pt
/// 会在边缘留出一圈 1pt 的外层材质，快照上可分辨。
/// 纯装饰：不拦鼠标（`hitTest` 返回 nil）、不参与布局计算、不改卡片与面板宽度档位。
@MainActor
final class ClipboardPanelInnerMaterialView: NSVisualEffectView {

    /// 内衬圆角（外层 14pt，小 2pt 才能在内缩后留出完整的一圈外层材质）
    static let cornerRadius: CGFloat = 12

    /// 相对面板边界的内缩（两级材质之间那圈 1pt）
    static let inset: CGFloat = 1

    init() {
        super.init(frame: .zero)
        material = .underWindowBackground
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = Self.cornerRadius
        layer?.masksToBounds = true
        // 跟随面板尺寸：内缩量固定，宽高各随父视图伸缩，不需要每次 layout 重算
        autoresizingMask = [.width, .height]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持从 nib 初始化") }

    /// 装饰层不吃鼠标事件：点击仍落到内衬之上的控件与卡片
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// MARK: - 发丝分隔线

/// 面板发丝分隔线层 — 工具条底部、提示行顶部各一条（设计稿口径）
///
/// 内衬作为子视图会盖住父视图自绘的线条，因此分隔线单独成层，紧跟内衬、位于所有控件与卡片之下
/// （与改动前「父视图自绘在子视图之下」的层次一致，外观不回退）。
/// 纵坐标由面板视图在 `layout()` 里灌入（与工具条 / 提示行同源，不在此处复制高度常量）。
@MainActor
final class ClipboardPanelSeparatorView: NSView {

    /// 各条分隔线的纵坐标（翻转坐标，自上而下）；由面板视图在 layout 时写入
    var linePositions: [CGFloat] = [] {
        didSet {
            guard linePositions != oldValue else { return }
            needsDisplay = true
        }
    }

    override var isFlipped: Bool { true }

    /// 装饰层不吃鼠标事件
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.withAlphaComponent(0.5).setFill()
        for y in linePositions {
            NSRect(x: 0, y: y, width: bounds.width, height: 1).fill()
        }
    }
}

// MARK: - 面板视图的材质 / 分隔线接线

/// 两个装饰层的布局接线 —— 放在本文件，避免「ClipboardPanelView」主文件继续膨胀
extension ClipboardPanelView {

    /// 按面板边界同步两个装饰层：内衬内缩固定量且不参与布局计算，分隔线坐标与工具条 / 提示行同源
    ///
    /// - Parameters:
    ///   - toolbarHeight: 工具条高度（第一条分隔线落在其底部）
    ///   - footerHeight: 提示行顶部纵坐标（翻转坐标，自上而下）
    func layoutPanelChrome(toolbarHeight: CGFloat, footerHeight: CGFloat) {
        let inset = ClipboardPanelInnerMaterialView.inset
        innerMaterial.frame = bounds.insetBy(dx: inset, dy: inset)
        separatorView.frame = bounds
        separatorView.linePositions = [toolbarHeight, footerHeight]
    }
}
