import AppKit

// MARK: - 迷你折线

/// 单序列迷你折线 — 高度固定、宽度由外部撑满；`fixedMaximum` 让并列图表共用纵轴
///
/// 折线下方是**同族纵向渐变**（顶部浓、底部透明）：面积让「高低」一眼可读，
/// 渐变把色相数量压住（定稿 B 手法），不再用整块 20% 平涂。
final class SystemSparklineView: NSView {

    /// 采样值（越靠后越新）
    var values: [Double] = [] {
        didSet {
            guard values != oldValue else { return }
            needsDisplay = true
        }
    }

    /// 折线色（语义色，深浅色自适应）
    var lineColor: NSColor = SystemPalette.cpu {
        didSet { needsDisplay = true }
    }

    /// 固定纵轴上限（nil = 取自身最大值）
    var fixedMaximum: Double? {
        didSet { needsDisplay = true }
    }

    /// 是否在折线下方填充同族渐变面积
    private let fillsArea: Bool

    /// - Parameter lineColor: nil 时取 CPU 族主色（默认参数在非隔离上下文求值，
    ///   不能直接写 `SystemPalette.cpu`，否则 Swift 6 报「main actor-isolated 属性」错误）
    init(lineColor: NSColor? = nil, height: CGFloat = 12, fillsArea: Bool = true) {
        self.lineColor = lineColor ?? SystemPalette.cpu
        self.fillsArea = fillsArea
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: height).isActive = true
        setAccessibilityRole(.image)
        setAccessibilityLabel("趋势曲线")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        // 绘制只留一份（SystemChartDrawing）：自绘卡片复用同一个函数，两条路径不会画出两种图
        SystemChartDrawing.drawSparkline(values: values, in: bounds, lineColor: lineColor,
                                         fixedMaximum: fixedMaximum, fillsArea: fillsArea,
                                         trackColor: SystemPalette.track)
    }
}

// MARK: - 面积图

/// 60 秒面积图 — 三条参考线 + 同族渐变面积 + 折线（高低一眼可读，不写坐标）
///
/// 两种画法：
/// - 单序列（默认）：`values` 一条渐变面积 + 折线；
/// - 叠加序列（`overlayValues` 与 `values` 等长时）：`values` 仍是总占用（带顶线），
///   底层为「总量 − 叠加量」的渐变面积，其上为叠加量构成的实心带 —— 即 CPU 用户态 / 系统态。
///
/// **叠加模式纵轴固定 0…1，单序列模式才自适应**：带的厚度就是「系统态真实占比」这一语义，
/// 自适应纵轴会把 2% 的系统态在 20% 总量下画成 10% 画布高（看着占三分之一、卡面却写 15%），
/// 图在说谎。百分比与画布高度必须一一对应。单序列只看形状，自适应无害，维持原样。
final class SystemAreaChartView: NSView {

    /// 采样值（通常即 CPU 总利用率）
    var values: [Double] = [] {
        didSet {
            guard values != oldValue else { return }
            needsDisplay = true
        }
    }

    /// 叠加层序列（通常即 CPU 系统态占比）；与 `values` 等长才叠加，否则忽略
    var overlayValues: [Double] = [] {
        didSet {
            guard overlayValues != oldValue else { return }
            needsDisplay = true
        }
    }

    /// 叠加层颜色（系统态带用同族第二个蓝）
    var overlayColor: NSColor = SystemPalette.cpuSecondary {
        didSet { needsDisplay = true }
    }

    var lineColor: NSColor = SystemPalette.cpu {
        didSet { needsDisplay = true }
    }

    /// 固定纵轴上限（GPU 详情页固定 0–10% 量程时用；nil = 自适应 / 叠加模式固定 1）
    var fixedMaximum: Double? {
        didSet { needsDisplay = true }
    }

    init(height: CGFloat = 44) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: height).isActive = true
        setAccessibilityRole(.image)
        setAccessibilityLabel("利用率面积趋势")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        // 绘制只留一份（SystemChartDrawing）：自绘卡片复用同一个函数，两条路径不会画出两种图
        SystemChartDrawing.drawAreaChart(values: values, overlayValues: overlayValues,
                                         in: bounds, lineColor: lineColor,
                                         overlayColor: overlayColor,
                                         fixedMaximum: fixedMaximum,
                                         gridColor: SystemPalette.grid)
    }
}
