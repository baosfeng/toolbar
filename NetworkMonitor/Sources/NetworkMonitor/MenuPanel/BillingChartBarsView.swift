import AppKit
import NetworkMonitorCore
import NetworkMonitorDesign
import NetworkMonitorUI

// MARK: - 额度柱图（基线 + 柱 + 水平网格 + 左侧峰值刻度）

/// 跨 provider 汇总柱图 —— 自基线向上生长的实心柱，4 条水平网格 + 左侧刻度
///
/// 从 BillingChartRows.swift 拆出（几何口径已下沉到 NetworkMonitorUI 的
/// `BillingChartGeometry`，本文件只做绘制与鼠标命中）。
///
/// 改造前后差异（每条都有实测依据，见 docs 调研 6.3）：
/// - 改造前每根柱先画满高轨道再叠填充，视觉是「一排灰框 + 顶部一小截色」，低值柱悬空；
///   现在没有轨道，只有一条基线，柱从基线长上来，读法与其他柱状图一致。
/// - 改造前无刻度、无网格，柱之间只能比高矮、读不出绝对量；现在 4 条网格 + 左侧刻度
///   （峰值 / 3 档中点），刻度与柱高共用同一个归一化基准。
/// - 改造前当前柱用文本强调色 `accentText`（与其余柱不同色系）；现在统一用图表语义色，
///   当前柱靠不透明度区分（其余 0.72、当前与悬停 1.0），不加花哨动效。
@MainActor
final class BillingChartBarsView: NSView {

    private var points: [BillingChartAggregate.ChartPoint] = []
    private var metric: BillingChartAggregate.Metric = .requests
    private var granularity: BillingGranularity = .day
    private var fillColor: NSColor = PaneCardStyle.uncachedColor
    private var hoveredIndex: Int?
    private var trackingAreaRef: NSTrackingArea?

    /// 非当前柱的不透明度 —— 只差一层，够分辨又不刺眼
    static let restingAlpha: CGFloat = 0.72
    /// 空态时柱区高度（与 BillingChartsSectionView.barHeight 同源，保留 intrinsic 兜底）
    static let defaultHeight: CGFloat = BillingChartsSectionView.barHeight

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityRole(.group)
        setAccessibilityLabel("用量柱状图")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    /// 一帧数据
    ///
    /// - Parameters:
    ///   - points: 图表点（已按页级范围合并）
    ///   - metric: 请求数 / 金额（决定刻度与悬停文案的写法）
    ///   - granularity: 目标粒度（决定悬停写「时」还是「日」）
    ///   - fillColor: 柱色（跟随指标语义色，当前柱不再另取强调色）
    func update(points: [BillingChartAggregate.ChartPoint],
                metric: BillingChartAggregate.Metric,
                granularity: BillingGranularity,
                fillColor: NSColor) {
        self.points = points
        self.metric = metric
        self.granularity = granularity
        self.fillColor = fillColor
        updateAccessibility()
        needsDisplay = true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Self.defaultHeight)
    }

    // MARK: - 几何

    /// 是否画左侧刻度栏（矮图不画：44pt 的二级页柱区里刻度会压住柱子）
    private var showsScale: Bool { bounds.height >= BillingChartGeometry.scaleMinHeight }

    /// 本帧的网格档位（大图 4 条、小图 2 条）
    private var gridFractions: [CGFloat] {
        BillingChartGeometry.gridFractions(forHeight: bounds.height)
    }

    /// 刻度栏宽度 = 最长刻度标签宽 + 4pt 间隙（下限 20pt）
    ///
    /// 量文字必须在视图层（UI 库不 import AppKit），「画哪几个值」仍由纯函数给。
    var scaleGutter: CGFloat {
        guard showsScale else { return 0 }
        let font = PaneCardStyle.axisFont
        let widest = gridFractions
            .map { BillingChartGeometry.tickLabel(peak: peak, fraction: $0, metric: metric) }
            .map { DrawnTextRun(string: $0, font: font, color: PaneCardStyle.tertiaryText).width() }
            .max() ?? 0
        return max(20, (widest + 4).rounded(.up))
    }

    /// 绘图区（左侧让出刻度栏）
    var plotRect: NSRect {
        let gutter = scaleGutter
        return NSRect(x: bounds.minX + gutter, y: bounds.minY,
                      width: max(1, bounds.width - gutter), height: bounds.height)
    }

    /// 归一化基准 = 单桶峰值（与刻度同一基准）
    private var peak: Double { max(points.map(\.value).max() ?? 0, 0) }

    /// 当前这一帧的柱矩形（命中断言与 draw 共用同一份）
    private var columns: [BillingChartGeometry.Column] {
        BillingChartGeometry.columns(points, in: plotRect)
    }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        guard !points.isEmpty, bounds.width > 0 else { return }
        let plot = plotRect
        drawGrid(in: plot)
        drawBaseline(in: plot)
        for column in columns where column.bar.height > 0 {
            let highlighted = column.isCurrent || column.index == hoveredIndex
            DrawnInk.fill(column.bar, radius: BillingChartGeometry.barRadius,
                          color: fillColor.withAlphaComponent(highlighted ? 1 : Self.restingAlpha))
        }
    }

    /// 水平网格 + 左侧刻度（与柱高同一基准，不另算一套）
    private func drawGrid(in plot: NSRect) {
        let fractions = gridFractions
        let line = NSBezierPath()
        for fraction in fractions {
            let y = BillingChartGeometry.gridLineY(fraction: fraction, in: plot)
            line.move(to: NSPoint(x: plot.minX, y: y))
            line.line(to: NSPoint(x: plot.maxX, y: y))
        }
        line.lineWidth = 1
        line.setLineDash([2, 3], count: 2, phase: 0)
        PaneCardStyle.gridLine.setStroke()
        line.stroke()

        guard showsScale else { return }
        let font = PaneCardStyle.axisFont
        for fraction in fractions {
            let text = BillingChartGeometry.tickLabel(peak: peak, fraction: fraction, metric: metric)
            let run = DrawnTextRun(string: text, font: font, color: PaneCardStyle.tertiaryText)
            let y = BillingChartGeometry.gridLineY(fraction: fraction, in: plot)
            // 上下都夹进绘图区：顶档与底档的字不出框（顶档越出会压住卡头那行说明）
            let top = min(max(y - run.lineHeight / 2, 0), max(bounds.height - run.lineHeight, 0))
            run.draw(in: CGRect(x: bounds.minX, y: top,
                                width: max(plot.minX - bounds.minX - 4, 1),
                                height: run.lineHeight), alignment: .right)
        }
    }

    /// 基线（1pt 实线）—— 没有它柱就是悬空的色块，这正是「不像柱状图」的主因
    private func drawBaseline(in plot: NSRect) {
        PaneCardStyle.ghostColor.setFill()
        CGRect(x: plot.minX, y: plot.maxY - BillingChartGeometry.baselineHeight,
               width: plot.width, height: BillingChartGeometry.baselineHeight).fill()
    }

    // MARK: - 悬停

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef { removeTrackingArea(trackingAreaRef) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .mouseMoved,
                                            .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseMoved(with event: NSEvent) {
        guard !points.isEmpty else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard let index = BillingChartGeometry.columnIndex(at: point.x, columns: columns) else {
            clearHover()
            return
        }
        hoveredIndex = index
        toolTip = Self.caption(points[index], granularity: granularity, metric: metric)
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        clearHover()
    }

    private func clearHover() {
        guard hoveredIndex != nil else { return }
        hoveredIndex = nil
        toolTip = nil
        needsDisplay = true
    }

    /// 单根柱的悬停文案：标签 + 粒度单位 + 数值
    ///
    /// 24h 按小时、7d / 30d 按天（粒度唯一真源是 `BillingChartAggregate.granularity`）。
    static func caption(_ point: BillingChartAggregate.ChartPoint,
                        granularity: BillingGranularity,
                        metric: BillingChartAggregate.Metric) -> String {
        BillingChartGeometry.caption(point, granularity: granularity, metric: metric)
    }

    private func updateAccessibility() {
        guard !points.isEmpty else {
            setAccessibilityLabel("用量柱状图，暂无数据")
            return
        }
        let unit = BillingChartGeometry.captionUnit(for: granularity)
        let peakPoint = points.max { $0.value < $1.value }
        let detail = peakPoint.map {
            "峰值 " + BillingChartGeometry.caption($0, granularity: granularity, metric: metric)
        } ?? ""
        setAccessibilityLabel("用量柱状图，" + detail + (detail.isEmpty ? "" : "，" + unit + "粒度"))
    }
}