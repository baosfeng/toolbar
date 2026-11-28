import AppKit
import NetworkMonitorCore

// MARK: - Token 主图（三段堆叠柱 / 请求数柱 / 双折线对比 + 累计虚线）
//
// 小图表（走势 / 迷你柱 / 命中率环 / 分布条）见 TokenMiniChartViews.swift。

/// 主图：三段堆叠柱 / 请求数柱 / 本周期 vs 上一周期双折线 + 累计虚线
///
/// 口径：柱高按当前序列的单桶峰值归一（堆叠取 total、请求数取 request）；对比态不画柱，只画两条折线（实线本周期、虚线对照），
/// 视觉按原型 `.cumlay` 的 cmpA / cmpB；每列可点开二级页（点击按 x 命中，点击区覆盖整列）。
final class TokenBarsView: NSView {

    /// 柱形态
    enum Shape {
        case stack
        case request
        case pair
    }

    var onSelect: ((Int) -> Void)?

    // 跨文件访问（`TokenBarsView+Hover` 的悬停命中要读列数与单列数据）故去掉 private
    var buckets: [TokenBucket] = []
    private var previous: [TokenBucket] = []
    private var cumulative: [Double] = []
    private var shape: Shape = .stack
    private var showsCumulative = false
    /// 对比态按哪个指标画（请求数 / 三段总量）
    private var pairMetric: TokenMetric = .request
    /// 显式归一化基准（nil = 用本序列峰值；二级页跨序列对比时传入）
    private var scaleMax: Int?
    /// 是否画左侧刻度（0 / 中值 / 峰值）与 4 条水平网格虚线（用量屏主图开；二级页小图不开）
    private var showsScale = false
    /// 桶是否为小时桶（今日 24 桶 = true；按天 = false）—— 只影响悬停文案里的「小时 / 天」
    ///
    /// 跨文件访问（`TokenBarsView+Hover` 读）故去掉 private。
    var isHourBuckets = true
    /// 当前悬停的列（nil = 没有悬停）—— 画的时候在该列描一道边，鼠标落在哪根柱上一眼可见
    var hoveredIndex: Int?
    /// 悬停追踪区（每次 updateTrackingAreas 重建，先摘旧的）
    var trackingAreaRef: NSTrackingArea?

    /// 刻度栏最小宽度（窄刻度不白占宽度）
    static let minScaleGutter: CGFloat = 22
    /// 左侧刻度栏宽度 —— 按当前刻度的最长标签现算（横轴刻度行读同一个值，柱与刻度才对得齐）
    ///
    /// 改前写死 34pt：\"1.128亿\" 这类七字符刻度宽约 45pt，右对齐后左端跑到 x < 0，
    /// 首字符被视图裁掉（用量屏左侧刻度「112.8 万」「3056.4 万」都被切了头）。
    private(set) var scaleGutter: CGFloat = TokenBarsView.minScaleGutter

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityRole(.group)
        setAccessibilityLabel("柱图")
        setAccessibilityHelp("点击任一柱可打开该时段详情")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func update(buckets: [TokenBucket],
                previous: [TokenBucket] = [],
                cumulative: [Double] = [],
                shape: Shape,
                showsCumulative: Bool,
                pairMetric: TokenMetric = .request,
                scaleMax: Int? = nil,
                showsScale: Bool = false,
                isHourBuckets: Bool = true,
                accessibility: String) {
        self.buckets = buckets
        self.isHourBuckets = isHourBuckets
        self.previous = previous
        self.cumulative = cumulative
        self.shape = shape
        self.showsCumulative = showsCumulative
        self.pairMetric = pairMetric
        self.scaleMax = scaleMax
        self.showsScale = showsScale
        // 刻度栏宽度跟着这批刻度的最长标签走：标签宽了栏跟着宽，不被裁；窄了不白占
        if showsScale { scaleGutter = Self.gutterWidth(for: resolvedScale()) }
        setAccessibilityLabel(accessibility)
        // 数据换了：旧列号可能越界，先清掉悬停态再重画（不清会画出不存在的提亮列）
        hoveredIndex = nil
        toolTip = nil
        needsDisplay = true
    }

    /// 绘图区：开了左侧刻度就右移刻度栏宽度（柱、折线、累计虚线共用同一块）
    var plotRect: NSRect {
        guard showsScale else { return bounds }
        return NSRect(x: bounds.minX + scaleGutter, y: bounds.minY,
                      width: max(1, bounds.width - scaleGutter), height: bounds.height)
    }

    /// 对比值（仅对比态用）：请求数取 request，三段取总 tok
    private func pairValue(_ bucket: TokenBucket) -> Int {
        pairMetric == .request ? bucket.request : bucket.total
    }

    /// 对比态本周期线色（请求数用 requestColor、三段总量用 uncachedColor）
    ///
    /// 图例取色走这里，保证「图例色块 = 折线颜色」。
    var lineColor: NSColor {
        pairMetric == .request ? TokenPaneStyle.requestColor : TokenPaneStyle.uncachedColor
    }

    // MARK: 绘制

    override func draw(_ dirtyRect: NSRect) {
        guard !buckets.isEmpty else { return }
        let count = buckets.count
        let gap: CGFloat = 2
        let plot = plotRect
        let columnWidth = max(1, (plot.width - gap * CGFloat(count - 1)) / CGFloat(count))
        let scale = resolvedScale()

        // 网格在所有内容之下，柱 / 折线 / 累计虚线压在上面
        if showsScale { drawScale(scale: scale, in: plot) }

        if shape == .pair {
            // 对比态不画柱（原型 #hBars 直接隐藏），整幅只有两条折线
            drawPairLines(gap: gap, columnWidth: columnWidth, count: count, scale: scale)
        } else {
            drawColumns(gap: gap, columnWidth: columnWidth, scale: scale)
        }

        if showsCumulative, cumulative.count == count {
            drawCumulative(columnWidth: columnWidth, gap: gap, count: count)
        }

        // 悬停列描一道边（画在最上层，柱体颜色不动）：
        // 只用一个视觉信号——不叠色、不改透明度，主题换了也不用重调
        if let hoveredIndex, hoveredIndex < count {
            let column = columnRect(index: hoveredIndex, gap: gap, columnWidth: columnWidth)
            TokenPaneStyle.accentText.withAlphaComponent(0.55).setStroke()
            let outline = NSBezierPath(roundedRect: column.insetBy(dx: 0.5, dy: 0.5),
                                       xRadius: 2, yRadius: 2)
            outline.lineWidth = 1
            outline.stroke()
        }
    }

    /// 逐列画柱（堆叠 / 请求数两态共用）
    private func drawColumns(gap: CGFloat, columnWidth: CGFloat, scale: Int) {
        for index in buckets.indices {
            let x = plotRect.minX + CGFloat(index) * (columnWidth + gap)
            let column = NSRect(x: x, y: plotRect.minY, width: columnWidth, height: plotRect.height)
            if shape == .stack {
                drawStack(bucket: buckets[index], scale: scale, in: column)
            } else {
                drawRequest(bucket: buckets[index], scale: scale, in: column)
            }
        }
    }

    private func drawStack(bucket: TokenBucket, scale: Int, in column: NSRect) {
        TokenPaneStyle.trackColor.setFill()
        NSBezierPath(roundedRect: column, xRadius: 2, yRadius: 2).fill()
        guard bucket.total > 0 else { return }
        let heights = [Double(bucket.cache), Double(bucket.uncached), Double(bucket.output)]
            .map { $0 / Double(scale) * Double(column.height) }
        var offset = column.minY
        let colors = [TokenPaneStyle.cacheStackFill, TokenPaneStyle.uncachedColor, TokenPaneStyle.outputColor]
        for (index, height) in heights.enumerated() where height > 0 {
            let rect = NSRect(x: column.minX, y: offset, width: column.width, height: CGFloat(height))
            colors[index].setFill()
            NSBezierPath(rect: rect).fill()
            offset += CGFloat(height)
        }
    }

    private func drawRequest(bucket: TokenBucket, scale: Int, in column: NSRect) {
        TokenPaneStyle.trackColor.setFill()
        NSBezierPath(roundedRect: column, xRadius: 2, yRadius: 2).fill()
        guard bucket.request > 0 else { return }
        let height = Double(bucket.request) / Double(scale) * Double(column.height)
        let rect = NSRect(x: column.minX, y: column.minY, width: column.width, height: CGFloat(height))
        TokenPaneStyle.requestColor.setFill()
        NSBezierPath(rect: rect).fill()
    }

    /// 对比态折线：本周期实线 1.6pt、对照虚线 1.2pt（3 / 2.4 段，0.9 透明）
    ///
    /// 视觉取自原型 `.cumlay .cmpA / .cmpB`：点在列中心、两条线共用同一归一化基准；
    /// 颜色沿用既有语义色——请求数用 requestColor、三段总量用 uncachedColor，对照固定 ghostColor。
    private func drawPairLines(gap: CGFloat, columnWidth: CGFloat, count: Int, scale: Int) {
        let inset = TokenPaneStyle.pairLineInset
        let plot = plotRect
        let plotHeight = max(1, plot.height - inset * 2)

        func path(_ values: [TokenBucket]) -> NSBezierPath {
            let line = NSBezierPath()
            for index in 0..<count {
                let value = index < values.count ? pairValue(values[index]) : 0
                let x = plot.minX + (CGFloat(index) + 0.5) * (columnWidth + gap)
                let ratio = min(1, max(0, Double(value) / Double(scale)))
                let y = plot.minY + inset + CGFloat(ratio) * plotHeight
                if index == 0 {
                    line.move(to: NSPoint(x: x, y: y))
                } else {
                    line.line(to: NSPoint(x: x, y: y))
                }
            }
            return line
        }

        // 对照线先画（在下层），本周期线压在上面
        let previousPath = path(previous)
        previousPath.lineWidth = 1.2
        previousPath.lineJoinStyle = .round
        previousPath.lineCapStyle = .round
        previousPath.setLineDash([3, 2.4], count: 2, phase: 0)
        TokenPaneStyle.ghostColor.withAlphaComponent(0.9).setStroke()
        previousPath.stroke()

        let currentPath = path(buckets)
        currentPath.lineWidth = 1.6
        currentPath.lineJoinStyle = .round
        currentPath.lineCapStyle = .round
        lineColor.setStroke()
        currentPath.stroke()
    }

    private func drawCumulative(columnWidth: CGFloat, gap: CGFloat, count: Int) {
        guard let peak = cumulative.last, peak > 0 else { return }
        let path = NSBezierPath()
        for index in cumulative.indices {
            let x = plotRect.minX + (CGFloat(index) + 0.5) * (columnWidth + gap)
            let ratio = min(1, max(0, cumulative[index] / peak))
            let y = plotRect.minY + CGFloat(ratio) * plotRect.height
            if index == 0 { path.move(to: NSPoint(x: x, y: y)) } else { path.line(to: NSPoint(x: x, y: y)) }
        }
        path.lineWidth = 1.1
        path.setLineDash([2.4, 2.2], count: 2, phase: 0)
        TokenPaneStyle.secondaryText.withAlphaComponent(0.5).setStroke()
        path.stroke()
    }

    /// 单桶绘图值：堆叠态 = 三段之和（total）、请求数态 = 请求数、对比态 = 对比指标
    ///
    /// 与柱高 / 折线的画法同源：柱高按这个值归一，不能再另算一套口径。
    private func barValue(_ bucket: TokenBucket) -> Int {
        switch shape {
        case .stack: return bucket.total
        case .request: return bucket.request
        case .pair: return pairValue(bucket)
        }
    }

    /// 柱态归一基准 = 单桶峰值（不是序列求和：求和会把 24 根柱压成一个量级的零头）
    private func columnPeak(_ list: [TokenBucket]) -> Int {
        list.reduce(0) { Swift.max($0, barValue($1)) }
    }

    /// 实际归一化基准 = 显式 scaleMax，否则按形态取基准
    ///
    /// 柱态（堆叠 / 请求数）取单桶峰值；对比态取两条序列的峰值（原型 cmpA / cmpB 的 scCmp）。
    private func resolvedScale() -> Int {
        let base: Int
        switch shape {
        case .stack, .request: base = max(columnPeak(buckets), 1)
        case .pair: base = max(seriesPeak(buckets), seriesPeak(previous), 1)
        }
        return max(scaleMax ?? base, 1)
    }

    /// 折线态归一基准：序列峰值
    private func seriesPeak(_ list: [TokenBucket]) -> Int {
        list.reduce(0) { Swift.max($0, pairValue($1)) }
    }

    // MARK: 交互

    override func mouseUp(with event: NSEvent) {
        guard onSelect != nil, !buckets.isEmpty else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return }
        let plot = plotRect
        // 点在刻度栏里不算选中某一列（否则会误开最左那格）
        guard point.x >= plot.minX else { return }
        let ratio = max(0, min(0.9999, (point.x - plot.minX) / max(1, plot.width)))
        onSelect?(min(buckets.count - 1, Int(ratio * CGFloat(buckets.count))))
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if onSelect != nil { addCursorRect(bounds, cursor: .pointingHand) }
    }
}