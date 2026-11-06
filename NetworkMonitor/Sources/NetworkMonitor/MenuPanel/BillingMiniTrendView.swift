import AppKit

// MARK: - 额度页迷你走势（与 Token sparkline 同一语法）

/// 卡片内迷你走势 —— 1.4pt 折线，与 Token 分族卡标题行右侧的 sparkline 同一画法
///
/// 改前是「迷你柱（gap 1.5、最后一根强调色）」：与 Token 页的折线是两套图表语法，
/// 同屏并排时像两个不同的产品。统一后两页的小图都只有一种形态：折线。
final class BillingMiniTrendView: NSView {

    /// 固定高度
    static let preferredHeight: CGFloat = PaneCardStyle.sparkHeight

    private var values: [Double] = []

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Self.preferredHeight)
    }

    func update(values: [Double]) {
        self.values = values
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard values.count > 1, bounds.width > 0 else { return }
        let peak = max(values.max() ?? 1, 1)
        let line = NSBezierPath()
        for (index, value) in values.enumerated() {
            let x = bounds.minX + CGFloat(index) / CGFloat(values.count - 1) * bounds.width
            let y = bounds.minY + CGFloat(min(1, value / peak)) * (bounds.height - 2) + 1
            if index == 0 { line.move(to: NSPoint(x: x, y: y)) } else { line.line(to: NSPoint(x: x, y: y)) }
        }
        line.lineWidth = 1.4
        line.lineJoinStyle = .round
        line.lineCapStyle = .round
        PaneCardStyle.ghostColor.setStroke()
        line.stroke()
    }
}
