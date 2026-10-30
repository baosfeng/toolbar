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
        guard values.count >= 2 else {
            // 无数据：贴底一条轨道，避免整格空白被误读为渲染失败
            SystemPalette.track.setFill()
            NSRect(x: bounds.minX, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
            return
        }
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let maximum = max(fixedMaximum ?? values.max() ?? 0, 0.000_001)
        if fillsArea {
            let area = SystemChartDrawing.areaPath(values: values, in: rect, maximum: maximum)
            SystemPalette.fillVerticalGradient(area, in: rect, color: lineColor)
        }
        let line = SystemChartDrawing.linePath(values: values, in: rect, maximum: maximum)
        line.lineWidth = 1.5
        lineColor.setStroke()
        line.stroke()
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
        // 参考线 25% / 50% / 75%：给「高/低」一个刻度感，不写字
        SystemPalette.grid.setFill()
        for fraction: CGFloat in [0.25, 0.5, 0.75] {
            NSRect(x: bounds.minX, y: bounds.height * fraction,
                   width: bounds.width, height: 0.5).fill()
        }
        guard values.count >= 2 else { return }
        let rect = bounds.insetBy(dx: 0, dy: 1)
        let isOverlay = overlayValues.count == values.count
        // 叠加模式：纵轴固定 1.0（0…100%），带厚 = 真实占比；单序列：自适应取峰值保形状
        let maximum = fixedMaximum ?? (isOverlay ? 1 : max(values.max() ?? 0, 0.000_001))
        if isOverlay {
            // 底层 = 总量 − 叠加量（钳到 [0, 总量]）：带厚即叠加量的真实占比
            let base = zip(values, overlayValues).map { total, overlay in
                min(max(total, 0), max(0, total - max(overlay, 0)))
            }
            SystemPalette.fillVerticalGradient(
                SystemChartDrawing.areaPath(values: base, in: rect, maximum: maximum),
                in: rect, color: lineColor, topAlpha: 0.30, bottomAlpha: 0.03)
            overlayColor.setFill()
            SystemChartDrawing.bandPath(lower: base, upper: values,
                                       in: rect, maximum: maximum).fill()
        } else {
            SystemPalette.fillVerticalGradient(
                SystemChartDrawing.areaPath(values: values, in: rect, maximum: maximum),
                in: rect, color: lineColor)
        }
        let line = SystemChartDrawing.linePath(values: values, in: rect, maximum: maximum)
        line.lineWidth = 2
        lineColor.setStroke()
        line.stroke()
    }
}
