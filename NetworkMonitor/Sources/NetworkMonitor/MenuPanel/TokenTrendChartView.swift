import AppKit
import NetworkMonitorCore

// MARK: - 按天趋势（堆叠柱 / 折线）

/// 按天趋势图 —— 近 7 / 近 30 天，堆叠柱与折线两态
///
/// 堆叠柱：缓存读 → 输出 → 未缓存输入的升序堆叠；无会话日画斜纹；今天描边。
/// 折线：三条独立折线（缓存读按合计峰值、输出 / 未缓存输入按各自峰值），
/// 中间缺数据日断开，不跨空档连线。
final class TokenTrendChartView: NSView {

    private var cells: [TokenPaneModel.DayCell] = []
    private var todayKey = ""
    private var mode: TokenTrendMode = .stack

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: TokenPaneStyle.trendChartHeight)
    }

    /// 更新数据
    func update(cells: [TokenPaneModel.DayCell], todayKey: String, mode: TokenTrendMode) {
        self.cells = cells
        self.todayKey = todayKey
        self.mode = mode
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !cells.isEmpty, bounds.width > 10, bounds.height > 10 else { return }
        var peak = 0
        for cell in cells {
            if let usage = cell.usage { peak = max(peak, UsageTotal.of(usage)) }
        }
        peak = max(peak, 1)
        switch mode {
        case .stack: drawStacked(peak: peak)
        case .line: drawLines(peak: peak)
        }
    }

    // MARK: - 堆叠柱

    private func drawStacked(peak: Int) {
        let gap: CGFloat = cells.count > 10 ? 1.5 : 2
        let columnWidth = max(1, (bounds.width - gap * CGFloat(cells.count - 1)) / CGFloat(cells.count))
        for (index, cell) in cells.enumerated() {
            let x = CGFloat(index) * (columnWidth + gap)
            let columnRect = NSRect(x: x, y: 0, width: columnWidth, height: bounds.height)
            guard let usage = cell.usage, UsageTotal.of(usage) > 0 else {
                TokenChartSupport.drawHatch(in: columnRect, color: TokenPaneStyle.trackColor,
                                            spacing: cells.count > 10 ? 3 : 4)
                continue
            }
            let total = UsageTotal.of(usage)
            let stackHeight = max(3, CGFloat(Double(total) / Double(peak)) * (bounds.height - 2))
            let stackRect = NSRect(x: x, y: 0, width: columnWidth, height: stackHeight)
            drawStack(in: stackRect, usage: usage)
            if cell.day == todayKey {
                let outline = NSBezierPath(rect: stackRect.insetBy(dx: -0.5, dy: 0.5))
                outline.lineWidth = 1
                NSColor.labelColor.setStroke()
                outline.stroke()
            }
        }
    }

    /// 与小时图同口径的三色堆叠
    private func drawStack(in rect: NSRect, usage: HarnessTokenUsage) {
        let total = UsageTotal.of(usage)
        guard total > 0 else { return }
        let segments: [(value: Int, color: NSColor)] = [
            (usage.cacheRead, TokenPaneStyle.cacheColor),
            (usage.output, TokenPaneStyle.outputColor),
            (usage.uncachedInput, TokenPaneStyle.inputColor),
        ]
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5).addClip()
        var y = rect.minY
        var remaining = rect.height
        for (index, segment) in segments.enumerated() {
            guard segment.value > 0, remaining > 0 else { continue }
            let isLast = index == segments.count - 1
            let ratio = CGFloat(Double(segment.value) / Double(total))
            let height = isLast ? remaining : min(remaining, max(1.5, rect.height * ratio))
            segment.color.setFill()
            NSRect(x: rect.minX, y: y, width: rect.width, height: height).fill()
            y += height
            remaining -= height
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: - 折线

    private func drawLines(peak: Int) {
        let pad: CGFloat = 6
        let plotHeight = bounds.height - pad * 2
        var maxOutput = 1
        var maxInput = 1
        for cell in cells {
            guard let usage = cell.usage else { continue }
            maxOutput = max(maxOutput, usage.output)
            maxInput = max(maxInput, usage.uncachedInput)
        }
        let series: [(value: (HarnessTokenUsage) -> Int, maxValue: Int, color: NSColor, width: CGFloat)] = [
            ({ $0.cacheRead }, peak, TokenPaneStyle.cacheColor, 1.8),
            ({ $0.output }, maxOutput, TokenPaneStyle.outputColor, 1.3),
            ({ $0.uncachedInput }, maxInput, TokenPaneStyle.inputColor, 1.3),
        ]
        let count = CGFloat(cells.count)
        for item in series {
            let path = NSBezierPath()
            path.lineWidth = item.width
            path.lineJoinStyle = .round
            path.lineCapStyle = .round
            var open = false
            for (index, cell) in cells.enumerated() {
                guard let usage = cell.usage else {
                    open = false
                    continue
                }
                let value = item.value(usage)
                guard value > 0 else {
                    open = false
                    continue
                }
                let x = count <= 1 ? bounds.midX : CGFloat(index) / (count - 1) * bounds.width
                let ratio = min(1, Double(value) / Double(item.maxValue))
                let y = pad + CGFloat(ratio) * plotHeight
                let point = NSPoint(x: x, y: y)
                if open {
                    path.line(to: point)
                } else {
                    path.move(to: point)
                    open = true
                }
            }
            item.color.setStroke()
            path.stroke()
        }
    }
}
