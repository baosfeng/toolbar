import AppKit

// MARK: - 图表共用口径

/// 单核占用 — P 核在前、E 核在后，`isPerformance` 决定柱体明度
struct SystemCoreUsage: Equatable {
    /// 悬停气泡里显示的核号（如 "P1" / "E3"）
    let label: String
    /// 利用率 0...1
    let usage: Double
    /// 是否性能核（P 核）
    let isPerformance: Bool
}

/// 图表绘制共用 — 采样清洗、折线与面积路径、悬停气泡
enum SystemChartDrawing {

    /// 采样窗口（与 1 秒采样 / 60 秒窗口一致）
    static let sampleLimit = 60

    /// IOPS 绘图参考上限（次/秒）—— 0…3000 跨两个数量级，线性刻度会把日常量级全压到底部
    static let iopsReference: Double = 3_000

    /// IOPS 序列归一化到 0...1（对数刻度，仅用于形状可比；真实数值写在卡片文字上）
    static func iopsNormalized(_ values: [Double]) -> [Double] {
        let span = log10(1 + iopsReference)
        return values.map { value in
            guard value.isFinite, value > 0 else { return 0 }
            return min(1, log10(1 + value) / span)
        }
    }

    /// 清洗采样：只保留最近 `sampleLimit` 个点，非有限值归零
    static func sanitized(_ values: [Double], limit: Int = sampleLimit) -> [Double] {
        values.suffix(max(2, limit)).map { $0.isFinite ? max(0, $0) : 0 }
    }

    /// 折线路径（flipped 坐标系：y 越小越靠上）
    static func linePath(values: [Double], in rect: NSRect, maximum: Double) -> NSBezierPath {
        let path = NSBezierPath()
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        guard values.count >= 2, rect.width > 0, rect.height > 0 else { return path }
        let step = rect.width / CGFloat(values.count - 1)
        for (index, value) in values.enumerated() {
            let ratio = maximum > 0 ? min(1, max(0, value / maximum)) : 0
            let point = NSPoint(x: rect.minX + CGFloat(index) * step,
                                y: rect.minY + rect.height * CGFloat(1 - ratio))
            if index == 0 { path.move(to: point) } else { path.line(to: point) }
        }
        return path
    }

    /// 面积路径（折线 + 底边闭合）
    static func areaPath(values: [Double], in rect: NSRect, maximum: Double) -> NSBezierPath {
        let path = NSBezierPath()
        guard values.count >= 2, rect.width > 0, rect.height > 0 else { return path }
        let step = rect.width / CGFloat(values.count - 1)
        path.move(to: NSPoint(x: rect.minX, y: rect.maxY))
        for (index, value) in values.enumerated() {
            let ratio = maximum > 0 ? min(1, max(0, value / maximum)) : 0
            path.line(to: NSPoint(x: rect.minX + CGFloat(index) * step,
                                  y: rect.minY + rect.height * CGFloat(1 - ratio)))
        }
        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
        path.close()
        return path
    }

    /// 叠加带路径 — 下沿 `lower`、上沿 `upper` 闭合成带（CPU 用户态面积之上的系统态带）
    ///
    /// 两条序列必须同长：调用方负责对齐（长度不等时退化为单序列绘制，避免错位成假曲线）。
    static func bandPath(lower: [Double], upper: [Double], in rect: NSRect, maximum: Double) -> NSBezierPath {
        let path = NSBezierPath()
        guard lower.count >= 2, lower.count == upper.count, rect.width > 0, rect.height > 0 else { return path }
        let step = rect.width / CGFloat(lower.count - 1)
        func point(index: Int, value: Double) -> NSPoint {
            let ratio = maximum > 0 ? min(1, max(0, value / maximum)) : 0
            return NSPoint(x: rect.minX + CGFloat(index) * step,
                           y: rect.minY + rect.height * CGFloat(1 - ratio))
        }
        path.move(to: point(index: 0, value: upper[0]))
        for index in 1..<upper.count {
            path.line(to: point(index: index, value: upper[index]))
        }
        for index in stride(from: lower.count - 1, through: 0, by: -1) {
            path.line(to: point(index: index, value: lower[index]))
        }
        path.close()
        return path
    }

    /// 悬停气泡：深底 + 反色文字，横向贴边钳制（纵向由调用方给定）
    @MainActor
    static func drawTooltip(_ text: String, centerX: CGFloat, topY: CGFloat, within bounds: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: MenuPanelStyle.smallValueFont,
            .foregroundColor: NSColor.windowBackgroundColor,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let padding: CGFloat = 4
        let width = size.width + padding * 2
        let height = size.height + 2
        let x = min(max(bounds.minX, centerX - width / 2), max(bounds.minX, bounds.maxX - width))
        let y = min(max(bounds.minY, topY), max(bounds.minY, bounds.maxY - height))
        let rect = NSRect(x: x, y: y, width: width, height: height)
        MenuPanelStyle.dynamicLabel(alpha: 0.92).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
        (text as NSString).draw(at: NSPoint(x: rect.minX + padding, y: rect.minY + 1),
                                withAttributes: attributes)
    }
}

// MARK: - 迷你折线

/// 单序列迷你折线 — 高度固定、宽度由外部撑满；`fixedMaximum` 让并列图表共用纵轴
final class SystemSparklineView: NSView {

    /// 采样值（越靠后越新）
    var values: [Double] = [] {
        didSet {
            guard values != oldValue else { return }
            needsDisplay = true
        }
    }

    /// 折线色（语义色，深浅色自适应）
    var lineColor: NSColor = MenuPanelStyle.accentColor {
        didSet { needsDisplay = true }
    }

    /// 固定纵轴上限（nil = 取自身最大值）
    var fixedMaximum: Double? {
        didSet { needsDisplay = true }
    }

    /// 是否在折线下方填充半透明面积
    private let fillsArea: Bool

    init(lineColor: NSColor, height: CGFloat = 12, fillsArea: Bool = false) {
        self.lineColor = lineColor
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
            MenuPanelStyle.trackColor.setFill()
            NSRect(x: bounds.minX, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
            return
        }
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let maximum = max(fixedMaximum ?? values.max() ?? 0, 0.000_001)
        if fillsArea {
            lineColor.withAlphaComponent(0.20).setFill()
            SystemChartDrawing.areaPath(values: values, in: rect, maximum: maximum).fill()
        }
        let line = SystemChartDrawing.linePath(values: values, in: rect, maximum: maximum)
        line.lineWidth = 1.5
        lineColor.setStroke()
        line.stroke()
    }
}

// MARK: - 面积图

/// 60 秒面积图 — 三条参考线 + 半透明面积 + 折线（高低一眼可读，不写坐标）
///
/// 两种画法：
/// - 单序列（默认）：`values` 一条面积 + 折线；
/// - 叠加序列（`overlayValues` 与 `values` 等长时）：`values` 仍是总占用（带顶线），
///   底层为「总量 − 叠加量」的实心面积，其上为叠加量构成的深色带 —— 即 CPU 用户态 / 系统态。
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

    /// 叠加层颜色（系统态带用深一档的同族蓝）
    var overlayColor: NSColor = NSColor.secondaryLabelColor {
        didSet { needsDisplay = true }
    }

    var lineColor: NSColor = MenuPanelStyle.accentColor {
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
        MenuPanelStyle.trackColor.setFill()
        for fraction: CGFloat in [0.25, 0.5, 0.75] {
            NSRect(x: bounds.minX, y: bounds.height * fraction,
                   width: bounds.width, height: 0.5).fill()
        }
        guard values.count >= 2 else { return }
        let rect = bounds.insetBy(dx: 0, dy: 1)
        let isOverlay = overlayValues.count == values.count
        // 叠加模式：纵轴固定 1.0（0…100%），带厚 = 真实占比；单序列：自适应取峰值保形状
        let maximum = isOverlay ? 1 : max(values.max() ?? 0, 0.000_001)
        if isOverlay {
            // 底层 = 总量 − 叠加量（钳到 [0, 总量]）：带厚即叠加量的真实占比
            let base = zip(values, overlayValues).map { total, overlay in
                min(max(total, 0), max(0, total - max(overlay, 0)))
            }
            lineColor.withAlphaComponent(0.22).setFill()
            SystemChartDrawing.areaPath(values: base, in: rect, maximum: maximum).fill()
            overlayColor.setFill()
            SystemChartDrawing.bandPath(lower: base, upper: values, in: rect, maximum: maximum).fill()
        } else {
            lineColor.withAlphaComponent(0.18).setFill()
            SystemChartDrawing.areaPath(values: values, in: rect, maximum: maximum).fill()
        }
        let line = SystemChartDrawing.linePath(values: values, in: rect, maximum: maximum)
        line.lineWidth = 2
        lineColor.setStroke()
        line.stroke()
    }
}

// MARK: - 双色折线

/// 读写双色折线 — 两条序列共用同一纵轴上限，保证高度可比
final class SystemDualSparklineView: NSView {

    /// 主序列（磁盘读）采样值
    var primaryValues: [Double] = [] {
        didSet {
            guard primaryValues != oldValue else { return }
            needsDisplay = true
        }
    }

    /// 次序列（磁盘写）采样值
    var secondaryValues: [Double] = [] {
        didSet {
            guard secondaryValues != oldValue else { return }
            needsDisplay = true
        }
    }

    // 读曲线用项目强调色（与容量条同色系），写曲线保留橙（与状态栏 ↑ 橙一致）
    var primaryColor: NSColor = MenuPanelStyle.accentColor {
        didSet { needsDisplay = true }
    }

    var secondaryColor: NSColor = .systemOrange {
        didSet { needsDisplay = true }
    }

    /// 主序列的 IOPS 叠加（次/秒，原值；内部按对数刻度归一化后画虚线）
    var primaryOverlayValues: [Double] = [] {
        didSet {
            guard primaryOverlayValues != oldValue else { return }
            needsDisplay = true
        }
    }

    /// 次序列的 IOPS 叠加（次/秒，原值）
    var secondaryOverlayValues: [Double] = [] {
        didSet {
            guard secondaryOverlayValues != oldValue else { return }
            needsDisplay = true
        }
    }

    /// IOPS 虚线颜色：读 / 写各一档灰，与两条实线速率互不抢色
    var primaryOverlayColor: NSColor = NSColor.secondaryLabelColor {
        didSet { needsDisplay = true }
    }

    var secondaryOverlayColor: NSColor = NSColor.tertiaryLabelColor {
        didSet { needsDisplay = true }
    }

    init(height: CGFloat = 24) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: height).isActive = true
        setAccessibilityRole(.image)
        setAccessibilityLabel("磁盘读写速率与每秒操作数趋势")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let hasRate = primaryValues.count >= 2 || secondaryValues.count >= 2
        let hasOverlay = primaryOverlayValues.count >= 2 || secondaryOverlayValues.count >= 2
        guard hasRate || hasOverlay else {
            MenuPanelStyle.trackColor.setFill()
            NSRect(x: bounds.minX, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
            return
        }
        let rect = bounds.insetBy(dx: 1, dy: 1)

        // 1. 速率：实线，两条共用字节量级纵轴
        let maximum = max((primaryValues + secondaryValues).max() ?? 0, 0.000_001)
        for (points, color) in [(primaryValues, primaryColor), (secondaryValues, secondaryColor)] {
            guard points.count >= 2 else { continue }
            let path = SystemChartDrawing.linePath(values: points, in: rect, maximum: maximum)
            path.lineWidth = 1.25
            color.setStroke()
            path.stroke()
        }

        // 2. IOPS：虚线，对数刻度单独归一化（与字节轴无换算关系，仅看形状）
        for (points, color) in [(primaryOverlayValues, primaryOverlayColor),
                                (secondaryOverlayValues, secondaryOverlayColor)] {
            guard points.count >= 2 else { continue }
            let path = SystemChartDrawing.linePath(
                values: SystemChartDrawing.iopsNormalized(points), in: rect, maximum: 1)
            path.lineWidth = 1
            path.setLineDash([2, 2], count: 2, phase: 0)
            color.setStroke()
            path.stroke()
        }
    }
}
