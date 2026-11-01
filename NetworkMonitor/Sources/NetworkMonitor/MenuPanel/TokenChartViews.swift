import AppKit
import NetworkMonitorCore

// MARK: - Token 主图（三段堆叠柱 / 请求数柱 / 双折线对比 + 累计虚线）
//
// 小图表（走势 / 迷你柱 / 命中率环 / 分布条）见 TokenMiniChartViews.swift。

/// 主图：三段堆叠柱 / 请求数柱 / 本周期 vs 上一周期双折线 + 累计虚线
///
/// 口径：柱高按当前序列最大值归一；对比态不画柱，只画两条折线（实线本周期、虚线对照），
/// 视觉按原型 `.cumlay` 的 cmpA / cmpB；每列可点开二级页（点击按 x 命中，点击区覆盖整列）。
final class TokenBarsView: NSView {

    /// 柱形态
    enum Shape {
        case stack
        case request
        case pair
    }

    var onSelect: ((Int) -> Void)?

    private var buckets: [TokenBucket] = []
    private var previous: [TokenBucket] = []
    private var cumulative: [Double] = []
    private var shape: Shape = .stack
    private var showsCumulative = false
    /// 对比态按哪个指标画（请求数 / 三段总量）
    private var pairMetric: TokenMetric = .request
    /// 显式归一化基准（nil = 用本序列峰值；二级页跨序列对比时传入）
    private var scaleMax: Int?

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
                accessibility: String) {
        self.buckets = buckets
        self.previous = previous
        self.cumulative = cumulative
        self.shape = shape
        self.showsCumulative = showsCumulative
        self.pairMetric = pairMetric
        self.scaleMax = scaleMax
        setAccessibilityLabel(accessibility)
        needsDisplay = true
    }

    /// 对比值：请求数取 request，三段取总 tok
    private func pairValue(_ bucket: TokenBucket) -> Int {
        pairMetric == .request ? bucket.request : bucket.total
    }

    // MARK: 绘制

    override func draw(_ dirtyRect: NSRect) {
        guard !buckets.isEmpty else { return }
        let count = buckets.count
        let gap: CGFloat = 2
        let columnWidth = max(1, (bounds.width - gap * CGFloat(count - 1)) / CGFloat(count))
        // 对比态按两条序列各自峰值归一（原型 cmpA / cmpB 的 scCmp = max(本期峰, 对照峰)），
        // 柱态沿用既有求和基准不动（堆叠态与请求数态本轮冻结）
        let base = shape == .pair ? max(seriesPeak(buckets), seriesPeak(previous), 1)
                                  : max(metricPeak(buckets), 1)
        let scale = max(scaleMax ?? base, 1)

        if shape == .pair {
            // 对比态不画柱（原型 #hBars 直接隐藏），整幅只有两条折线
            drawPairLines(gap: gap, columnWidth: columnWidth, count: count, scale: scale)
        } else {
            drawColumns(gap: gap, columnWidth: columnWidth, scale: scale)
        }

        if showsCumulative, cumulative.count == count {
            drawCumulative(columnWidth: columnWidth, gap: gap, count: count)
        }
    }

    /// 逐列画柱（堆叠 / 请求数两态共用）
    private func drawColumns(gap: CGFloat, columnWidth: CGFloat, scale: Int) {
        for index in buckets.indices {
            let x = bounds.minX + CGFloat(index) * (columnWidth + gap)
            let column = NSRect(x: x, y: bounds.minY, width: columnWidth, height: bounds.height)
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
        let plotHeight = max(1, bounds.height - inset * 2)

        func path(_ values: [TokenBucket]) -> NSBezierPath {
            let line = NSBezierPath()
            for index in 0..<count {
                let value = index < values.count ? pairValue(values[index]) : 0
                let x = bounds.minX + (CGFloat(index) + 0.5) * (columnWidth + gap)
                let ratio = min(1, max(0, Double(value) / Double(scale)))
                let y = bounds.minY + inset + CGFloat(ratio) * plotHeight
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
        (pairMetric == .request ? TokenPaneStyle.requestColor : TokenPaneStyle.uncachedColor).setStroke()
        currentPath.stroke()
    }

    private func drawCumulative(columnWidth: CGFloat, gap: CGFloat, count: Int) {
        guard let peak = cumulative.last, peak > 0 else { return }
        let path = NSBezierPath()
        for index in cumulative.indices {
            let x = bounds.minX + (CGFloat(index) + 0.5) * (columnWidth + gap)
            let ratio = min(1, max(0, cumulative[index] / peak))
            let y = bounds.minY + CGFloat(ratio) * bounds.height
            if index == 0 { path.move(to: NSPoint(x: x, y: y)) } else { path.line(to: NSPoint(x: x, y: y)) }
        }
        path.lineWidth = 1.1
        path.setLineDash([2.4, 2.2], count: 2, phase: 0)
        TokenPaneStyle.secondaryText.withAlphaComponent(0.5).setStroke()
        path.stroke()
    }

    /// 柱态归一基准（既有口径：序列求和，非序列峰值——本轮不改）
    private func metricPeak(_ list: [TokenBucket]) -> Int {
        list.reduce(0) { $0 + pairValue($1) }
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
        let ratio = max(0, min(0.9999, (point.x - bounds.minX) / max(1, bounds.width)))
        onSelect?(min(buckets.count - 1, Int(ratio * CGFloat(buckets.count))))
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if onSelect != nil { addCursorRect(bounds, cursor: .pointingHand) }
    }
}
