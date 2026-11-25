import AppKit
import NetworkMonitorCore
import NetworkMonitorDesign
import NetworkMonitorUI

// MARK: - 图表件（模型分布 / 走势）

// 柱图已拆到 BillingChartBarsView.swift（几何口径下沉到 NetworkMonitorUI 的 BillingChartGeometry）。

// MARK: - 模型分布

/// 模型 Top N 分布 —— 模型名（等宽截断）+ 占比条 + 数值 + 百分比，四列一次画完
///
/// 行高 18pt、四行加标题为 83pt（原型 F1 实测）。整块自绘：四行乘四个标签
/// 若各建 NSTextField 就是十六个视图，而这张卡每次刷新都会重排。
@MainActor
final class BillingModelShareListView: NSView {

    /// 行高
    static let rowHeight: CGFloat = 18
    /// 标题行高
    static let headHeight: CGFloat = 16
    /// 占比条高度
    static let barHeight: CGFloat = 4

    private var models: [BillingChartAggregate.ModelShare] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityRole(.group)
        setAccessibilityLabel("按模型分布")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    func update(models: [BillingChartAggregate.ModelShare]) {
        guard models != self.models else { return }
        self.models = models
        invalidateIntrinsicContentSize()
        needsDisplay = true
        setAccessibilityLabel(Self.accessibilityText(models))
    }

    var isEmpty: Bool { models.isEmpty }

    override var intrinsicContentSize: NSSize {
        guard !models.isEmpty else { return NSSize(width: NSView.noIntrinsicMetric, height: 0) }
        return NSSize(width: NSView.noIntrinsicMetric,
                      height: Self.headHeight + CGFloat(models.count) * Self.rowHeight)
    }

    /// Top N 的真实条数（不含「其他」合并行）
    private var shownCount: Int { models.filter { !$0.isOther }.count }

    // MARK: - 列几何（表头与数据行共用，保证严格对齐）

    /// 一行的四列几何
    struct RowMetrics: Equatable {
        /// 名称列（贴左，可截断）
        let name: CGRect
        /// 占比条列（弹性）
        let bar: CGRect
        /// 数值列（贴右）
        let value: CGRect
        /// 百分比列（贴右）
        let share: CGRect
    }

    /// 数值列宽（「$1,204」这种最长形态放得下）
    static let valueWidth: CGFloat = 56
    /// 百分比列宽（「100%」）
    static let shareWidth: CGFloat = 30
    /// 列间距（数值与百分比之间必须留够，否则「$0.42」和「41%」粘成一串）
    static let columnGap: CGFloat = 6
    /// 名称列最大宽度（再长也不挤掉条形与两列数字）
    static let maxNameWidth: CGFloat = 84

    /// 四列几何（表头与数据行同一份，改一处两处一起对）
    static func metrics(width: CGFloat) -> RowMetrics {
        let shareW = min(Self.shareWidth, max(width, 0))
        let share = CGRect(x: max(width - shareW, 0), y: 0,
                           width: shareW, height: rowHeight)
        let valueRight = max(share.minX - columnGap, 0)
        let valueW = min(Self.valueWidth, valueRight)
        let value = CGRect(x: valueRight - valueW, y: 0,
                           width: valueW, height: rowHeight)
        let nameW = min(maxNameWidth, max(value.minX - columnGap, 20))
        let name = CGRect(x: 0, y: 0, width: nameW, height: rowHeight)
        let barX = name.maxX + columnGap
        let bar = CGRect(x: barX, y: 0,
                         width: max(value.minX - columnGap - barX, 8), height: rowHeight)
        return RowMetrics(name: name, bar: bar, value: value, share: share)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !models.isEmpty, bounds.width > 0 else { return }
        let layout = Self.metrics(width: bounds.width)

        // 表头：标题贴左；「值」「占比」分别对齐到下面两列（不拼成一整串）
        let headRun = DrawnTextRun(string: "按模型分布 · Top " + String(shownCount),
                                   font: PaneCardStyle.cardTitleFont,
                                   color: PaneCardStyle.primaryText)
        // 标题可以占到「值」列之前：这一行左侧没有条形与数字，标题才是主角
        headRun.draw(topIn: CGRect(x: 0, y: 0, width: max(layout.value.minX - 4, 60),
                                   height: Self.headHeight))
        let valueHead = DrawnTextRun(string: "值", font: PaneCardStyle.axisFont,
                                     color: PaneCardStyle.tertiaryText)
        valueHead.draw(topIn: CGRect(x: layout.value.minX, y: 1, width: layout.value.width,
                                     height: Self.headHeight), alignment: .right)
        let shareHead = DrawnTextRun(string: "占比", font: PaneCardStyle.axisFont,
                                     color: PaneCardStyle.tertiaryText)
        shareHead.draw(topIn: CGRect(x: layout.share.minX + 4, y: 1,
                                     width: max(layout.share.width - 4, 10),
                                     height: Self.headHeight), alignment: .right)

        for (index, model) in models.enumerated() {
            drawRow(model, at: Self.headHeight + CGFloat(index) * Self.rowHeight, layout: layout)
        }
    }

    private func drawRow(_ model: BillingChartAggregate.ModelShare, at top: CGFloat,
                         layout: RowMetrics) {
        let rowMid = top + Self.rowHeight / 2

        let nameRun = DrawnTextRun(string: model.name, font: PaneCardStyle.modelNameFont,
                                   color: model.isOther ? PaneCardStyle.tertiaryText
                                                        : PaneCardStyle.secondaryText)
        nameRun.draw(in: CGRect(x: layout.name.minX, y: top, width: layout.name.width,
                                height: Self.rowHeight))

        let barRect = CGRect(x: layout.bar.minX, y: rowMid - Self.barHeight / 2,
                             width: layout.bar.width, height: Self.barHeight)
        DrawnInk.fill(barRect, radius: Self.barHeight / 2, color: PaneCardStyle.trackColor)
        let filled = max(barRect.width * CGFloat(min(max(model.share, 0), 1)), 1)
        DrawnInk.fill(CGRect(x: barRect.minX, y: barRect.minY, width: filled, height: barRect.height),
                      radius: Self.barHeight / 2,
                      color: model.isOther ? PaneCardStyle.ghostColor : PaneCardStyle.outputColor)

        let valueRun = DrawnTextRun(string: model.valueLabel, font: PaneCardStyle.axisFont,
                                    color: PaneCardStyle.secondaryText)
        valueRun.draw(in: CGRect(x: layout.value.minX, y: top, width: layout.value.width,
                                 height: Self.rowHeight), alignment: .right)

        let shareRun = DrawnTextRun(string: Self.percentText(model.share),
                                    font: PaneCardStyle.rowValueStrongFont,
                                    color: model.isOther ? PaneCardStyle.tertiaryText
                                                         : PaneCardStyle.primaryText)
        shareRun.draw(in: CGRect(x: layout.share.minX + 4, y: top,
                                 width: max(layout.share.width - 4, 10), height: Self.rowHeight),
                      alignment: .right)
    }

    /// 占比文案（整数百分，四舍五入）
    static func percentText(_ share: Double) -> String {
        String(Int((min(max(share, 0), 1) * 100).rounded())) + "%"
    }

    static func accessibilityText(_ models: [BillingChartAggregate.ModelShare]) -> String {
        guard !models.isEmpty else { return "按模型分布，暂无数据" }
        let parts = models.map { $0.name + " " + $0.valueLabel + " " + percentText($0.share) }
        return "按模型分布，" + parts.joined(separator: "，")
    }
}

// MARK: - 30 天走势

/// 30 天走势 —— 1.4pt 折线 + 末端强调点，与 Token 页 sparkline 同语言
///
/// 只负责形状：点数已由 BillingAggregate.chart 压到十根以内，
/// 因此不会出现三十个点挤成噪点；数据为空时整卡隐藏（由调用方控制）。
@MainActor
final class BillingTrendLineView: NSView {

    private var points: [BillingChartAggregate.ChartPoint] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityRole(.group)
        setAccessibilityLabel("近 30 天走势")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    func update(points: [BillingChartAggregate.ChartPoint]) {
        self.points = points
        setAccessibilityLabel(Self.accessibilityText(points))
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard points.count > 1, bounds.width > 0 else { return }
        let peak = max(points.map(\.value).max() ?? 0, 1)
        let bottom = bounds.maxY - 3
        let usable = max(bounds.height - 6, 1)
        let line = NSBezierPath()
        var last = CGPoint.zero
        for (index, point) in points.enumerated() {
            let x = bounds.minX + CGFloat(index) / CGFloat(points.count - 1) * bounds.width
            let y = bottom - CGFloat(min(max(point.value / peak, 0), 1)) * usable
            last = CGPoint(x: x, y: y)
            if index == 0 { line.move(to: last) } else { line.line(to: last) }
        }
        line.lineWidth = 1.4
        line.lineJoinStyle = .round
        line.lineCapStyle = .round
        PaneCardStyle.cacheColor.setStroke()
        line.stroke()
        DrawnInk.fill(CGRect(x: last.x - 1.5, y: last.y - 1.5, width: 3, height: 3),
                      radius: 1.5, color: PaneCardStyle.accentText)
    }

    static func accessibilityText(_ points: [BillingChartAggregate.ChartPoint]) -> String {
        guard !points.isEmpty else { return "近 30 天走势，暂无数据" }
        let peak = points.max { $0.value < $1.value }
        let detail = peak.map { "峰值 " + String(format: "%.0f", $0.value) } ?? ""
        return "近 30 天走势，" + detail
    }
}
