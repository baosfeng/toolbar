import AppKit
import NetworkMonitorCore

// MARK: - Token 页图表视图（柱 / 折线 / 环 / 分布条 / 坐标轴）

/// 主图：三段堆叠柱 / 请求数柱 / 双列对比柱 + 累计虚线
///
/// 口径：柱高按当前序列最大值归一；对比态画本周期与上一周期两条折线；
/// 每根柱可点开二级页（点击按 x 命中，点击区覆盖整列）。
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
        let peakValue = max(metricPeak(buckets), 1)
        let previousPeak = max(metricPeak(previous), 1)
        let scale = max(scaleMax ?? (shape == .pair ? max(peakValue, previousPeak) : peakValue), 1)

        for index in buckets.indices {
            let x = bounds.minX + CGFloat(index) * (columnWidth + gap)
            let column = NSRect(x: x, y: bounds.minY, width: columnWidth, height: bounds.height)
            switch shape {
            case .stack:
                drawStack(bucket: buckets[index], scale: scale, in: column)
            case .request:
                drawRequest(bucket: buckets[index], scale: scale, in: column)
            case .pair:
                drawPair(current: buckets[index],
                         previous: index < previous.count ? previous[index] : .empty,
                         scale: scale,
                         in: column)
            }
        }

        if showsCumulative, cumulative.count == count {
            drawCumulative(columnWidth: columnWidth, gap: gap, count: count)
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

    private func drawPair(current: TokenBucket, previous: TokenBucket, scale: Int, in column: NSRect) {
        let pairGap: CGFloat = 1
        let width = max(1, (column.width - pairGap) / 2)
        let currentRect = NSRect(x: column.minX, y: column.minY, width: width, height: column.height)
        let previousRect = NSRect(x: column.minX + width + pairGap, y: column.minY,
                                  width: width, height: column.height)
        TokenPaneStyle.trackColor.setFill()
        NSBezierPath(roundedRect: currentRect, xRadius: 2, yRadius: 2).fill()
        TokenPaneStyle.rowAltFill.setFill()
        NSBezierPath(roundedRect: previousRect, xRadius: 2, yRadius: 2).fill()

        let currentValue = pairValue(current)
        let previousValue = pairValue(previous)
        if currentValue > 0 {
            let height = Double(currentValue) / Double(scale) * Double(column.height)
            TokenPaneStyle.requestColor.setFill()
            NSBezierPath(rect: NSRect(x: currentRect.minX, y: currentRect.minY,
                                      width: currentRect.width, height: CGFloat(height))).fill()
        }
        if previousValue > 0 {
            let height = Double(previousValue) / Double(scale) * Double(column.height)
            TokenPaneStyle.ghostColor.setFill()
            NSBezierPath(rect: NSRect(x: previousRect.minX, y: previousRect.minY,
                                      width: previousRect.width, height: CGFloat(height))).fill()
        }
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

    private func metricPeak(_ list: [TokenBucket]) -> Int {
        list.reduce(0) { $0 + pairValue($1) }
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

/// sparkline / 面积折线（分族卡、天趋势卡、命中率走势共用）
final class TokenSparkView: NSView {

    private var values: [Double] = []
    private var fill: NSColor?
    private var stroke: NSColor = TokenPaneStyle.uncachedColor

    init(height: CGFloat,
         stroke: NSColor = TokenPaneStyle.uncachedColor,
         fill: NSColor? = nil) {
        self.stroke = stroke
        self.fill = fill
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([heightAnchor.constraint(equalToConstant: height)])
        setAccessibilityRole(.image)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func update(values: [Double], accessibility: String) {
        self.values = values
        setAccessibilityLabel(accessibility)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard values.count > 1 else { return }
        let peak = max(values.max() ?? 1, 1)
        let count = values.count
        let line = NSBezierPath()
        for index in values.indices {
            let x = bounds.minX + CGFloat(index) / CGFloat(count - 1) * bounds.width
            let y = bounds.minY + CGFloat(min(1, values[index] / peak)) * (bounds.height - 2) + 1
            if index == 0 { line.move(to: NSPoint(x: x, y: y)) } else { line.line(to: NSPoint(x: x, y: y)) }
        }
        if let fill {
            let area = line.copy() as? NSBezierPath ?? NSBezierPath()
            area.line(to: NSPoint(x: bounds.maxX, y: bounds.minY))
            area.line(to: NSPoint(x: bounds.minX, y: bounds.minY))
            area.close()
            fill.withAlphaComponent(0.55).setFill()
            area.fill()
        }
        line.lineWidth = 1.4
        line.lineJoinStyle = .round
        stroke.setStroke()
        line.stroke()
    }
}

/// 迷你柱（请求数分族卡）
final class TokenMiniBarsView: NSView {

    private var values: [Double] = []

    init(height: CGFloat) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([heightAnchor.constraint(equalToConstant: height)])
        setAccessibilityRole(.image)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func update(values: [Double], accessibility: String) {
        self.values = values
        setAccessibilityLabel(accessibility)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !values.isEmpty else { return }
        let peak = max(values.max() ?? 1, 1)
        let gap: CGFloat = 1
        let width = max(1, (bounds.width - gap * CGFloat(values.count - 1)) / CGFloat(values.count))
        for index in values.indices {
            let height = max(1, CGFloat(values[index] / peak) * bounds.height)
            let rect = NSRect(x: bounds.minX + CGFloat(index) * (width + gap),
                              y: bounds.minY,
                              width: width,
                              height: height)
            TokenPaneStyle.requestColor.withAlphaComponent(values[index] >= peak ? 1 : 0.85).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5).fill()
        }
    }
}

/// 缓存命中率环（30pt，环宽 3.4pt，中心一位小数字）
final class TokenRingView: NSView {

    private var rate: Double = 0
    private var centerText = "—"

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: TokenPaneStyle.ringSize),
            heightAnchor.constraint(equalToConstant: TokenPaneStyle.ringSize),
        ])
        setAccessibilityRole(.progressIndicator)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func update(rate: Double, text: String, accessibility: String) {
        self.rate = max(0, min(1, rate))
        centerText = text
        setAccessibilityLabel(accessibility)
        setAccessibilityValue(Int(rate * 100))
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let inset = TokenPaneStyle.ringWidth / 2 + 0.5
        let rect = bounds.insetBy(dx: inset, dy: inset)
        let background = NSBezierPath(ovalIn: rect)
        background.lineWidth = TokenPaneStyle.ringWidth
        TokenPaneStyle.trackColor.setStroke()
        background.stroke()

        defer { drawCenterText() }
        guard rate > 0 else { return }
        let foreground = NSBezierPath()
        foreground.appendArc(withCenter: NSPoint(x: bounds.midX, y: bounds.midY),
                             radius: rect.width / 2,
                             startAngle: 90,
                             endAngle: 90 - CGFloat(rate) * 360,
                             clockwise: true)
        foreground.lineWidth = TokenPaneStyle.ringWidth
        foreground.lineCapStyle = .round
        TokenPaneStyle.cacheColor.setStroke()
        foreground.stroke()
    }

    /// 环内数字用手绘居中（与 SystemRingView 同法）：
    /// 用 NSTextField 贴中心点时，cell 自带内边距 + 单行 cell 顶对齐，实测「97.5」会偏上并溢出环。
    private func drawCenterText() {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: TokenPaneStyle.ringTextFont,
            .foregroundColor: TokenPaneStyle.cacheInk,
        ]
        let size = (centerText as NSString).size(withAttributes: attributes)
        (centerText as NSString).draw(at: NSPoint(x: bounds.midX - size.width / 2,
                                                  y: bounds.midY - size.height / 2),
                                      withAttributes: attributes)
    }
}

/// 分布条（项目 / 模型占比，一次性画完所有段）
final class TokenStackBarView: NSView {

    private var shares: [Double] = []
    private var colors: [NSColor] = []

    init(height: CGFloat = TokenPaneStyle.stackBarHeight) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([heightAnchor.constraint(equalToConstant: height)])
        setAccessibilityRole(.image)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func update(shares: [Double], colors: [NSColor], accessibility: String) {
        self.shares = shares
        self.colors = colors
        setAccessibilityLabel(accessibility)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        TokenPaneStyle.trackColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        var offset = bounds.minX
        for (index, share) in shares.enumerated() where share > 0 {
            let width = CGFloat(share) * bounds.width
            guard width > 0.5 else { continue }
            let rect = NSRect(x: offset, y: bounds.minY, width: width, height: bounds.height)
            colors[safe: index]?.setFill()
            NSBezierPath(rect: rect).fill()
            offset += width
        }
    }
}
