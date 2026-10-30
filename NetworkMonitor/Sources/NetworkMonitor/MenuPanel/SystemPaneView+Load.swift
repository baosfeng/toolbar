import AppKit
import NetworkMonitorCore

// MARK: - 负载三线

/// 负载三线折线 — 1 / 5 / 15 分钟均值 + 核数参考虚线（近 60 秒）
///
/// **量程不是固定 0–100%**：负载是就绪队列长度（可以远超核数），纵轴上限按
/// `cap = max(核数 × 1.2, 峰值 × 1.15)` 现算；核数参考线按 `核数 / cap` 的真实比例画，
/// 所以「三线越过虚线」直接读作「有进程在排队」，而不是靠刻度猜。
final class SystemLoadChartView: NSView {

    /// 1 分钟序列（主序列，最粗实线）
    var shortValues: [Double] = [] {
        didSet {
            guard shortValues != oldValue else { return }
            needsDisplay = true
        }
    }

    /// 5 分钟序列
    var mediumValues: [Double] = [] {
        didSet {
            guard mediumValues != oldValue else { return }
            needsDisplay = true
        }
    }

    /// 15 分钟序列（虚线细）
    var longValues: [Double] = [] {
        didSet {
            guard longValues != oldValue else { return }
            needsDisplay = true
        }
    }

    /// 逻辑核数（参考虚线的真实位置；0 表示不画参考线）
    var coreCount: Int = 0 {
        didSet {
            guard coreCount != oldValue else { return }
            needsDisplay = true
        }
    }

    /// 纵轴上限（由调用方按 cap 公式现算；≤0 时按峰值兜底）
    var axisMaximum: Double = 0 {
        didSet { needsDisplay = true }
    }

    init(height: CGFloat = 34) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        // 固定高度 + 纵向抗拉伸：压力卡是纵向 stack，默认会把图表拉满剩余空间，
        // 三条线被摊到整行高后贴在底边（实测图上「三线挤成一条」就是这个原因）
        let fixed = heightAnchor.constraint(equalToConstant: height)
        fixed.priority = .required
        fixed.isActive = true
        setContentHuggingPriority(.defaultHigh, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
        setAccessibilityRole(.image)
        setAccessibilityLabel("近 60 秒系统负载三线")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let hasData = shortValues.count >= 2 || mediumValues.count >= 2 || longValues.count >= 2
        guard hasData else {
            // 无数据：中线一条灰线，避免整格空白被误读成渲染失败
            MenuPanelStyle.trackColor.setFill()
            NSRect(x: bounds.minX, y: bounds.midY, width: bounds.width, height: 0.5).fill()
            return
        }
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let maximum = resolvedMaximum()

        // 1. 核数参考虚线（先画，压在曲线之下）
        if coreCount > 0 {
            let ratio = min(1, Double(coreCount) / maximum)
            let y = rect.minY + rect.height * CGFloat(1 - ratio)
            let reference = NSBezierPath()
            reference.move(to: NSPoint(x: rect.minX, y: y))
            reference.line(to: NSPoint(x: rect.maxX, y: y))
            reference.lineWidth = 1
            reference.setLineDash([2, 3], count: 2, phase: 0)
            SystemPaneStyle.loadCoreReference.setStroke()
            reference.stroke()
        }

        // 2. 三条序列：15m 虚线最细 → 1m 实线最粗（线宽 + 线型双重区分，为色觉障碍兜底）
        draw(series: longValues, color: SystemPaneStyle.loadLong,
             width: 1, dash: [3, 2], in: rect, maximum: maximum)
        draw(series: mediumValues, color: SystemPaneStyle.loadMedium,
             width: 1.3, dash: [], in: rect, maximum: maximum)
        draw(series: shortValues, color: SystemPaneStyle.loadShort,
             width: 1.6, dash: [], in: rect, maximum: maximum)
    }

    /// 纵轴上限：调用方给了就用，没给按三序列峰值兜底（避免 0 除法）
    private func resolvedMaximum() -> Double {
        if axisMaximum.isFinite, axisMaximum > 0 { return axisMaximum }
        let peak = (shortValues + mediumValues + longValues).filter { $0.isFinite }.max() ?? 0
        return max(peak, 0.000_001)
    }

    /// 单条序列
    private func draw(series: [Double], color: NSColor, width: CGFloat,
                      dash: [CGFloat], in rect: NSRect, maximum: Double) {
        guard series.count >= 2 else { return }
        let path = SystemChartDrawing.linePath(values: series, in: rect, maximum: maximum)
        path.lineWidth = width
        if !dash.isEmpty {
            path.setLineDash(dash, count: dash.count, phase: 0)
        }
        color.setStroke()
        path.stroke()
    }

    /// 量程口径（供卡头 toolTip 与测试共用）：`max(核数 × 1.2, 峰值 × 1.15)`
    ///
    /// 下限用核数保证「低负载时不要把噪声放大成满画布」，上限用峰值让三条线用满高度。
    static func axisMaximum(coreCount: Int, peak: Double) -> Double {
        let byCores = Double(max(coreCount, 0)) * 1.2
        let byPeak = (peak.isFinite ? max(peak, 0) : 0) * 1.15
        return max(byCores, byPeak, 1)
    }
}
