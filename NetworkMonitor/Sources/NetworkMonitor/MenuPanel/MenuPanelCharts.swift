import AppKit
import NetworkMonitorCore

// MARK: - 近 6 日流量柱状图

/// 近 N 日下行流量柱状图 — 自绘 NSView（不引入任何第三方图表依赖）
///
/// 结构（自上而下）：数值（9pt 等宽）→ 柱体（圆角 2pt，今天用强调色）→ 日期（9pt 等宽）。
/// 柱高按相对最大值归一化，数据全 0 时保留最小可见高度，避免「空图看着像坏了」。
final class MenuPanelBarsView: NSView {

    /// 单根柱子
    struct Bar: Equatable {
        /// 日期短标签（如 "10/16"）
        let label: String
        /// 数值（字节）
        let value: UInt64
        /// 数值文案（已格式化，如 "5.6 GB"）
        let valueText: String
        /// 是否今天（强调色高亮）
        let isToday: Bool

        init(label: String, value: UInt64, valueText: String, isToday: Bool) {
            self.label = label
            self.value = value
            self.valueText = valueText
            self.isToday = isToday
        }
    }

    /// 柱数据（时间正序：最左最早、最右今天）
    var bars: [Bar] = [] {
        didSet {
            guard bars != oldValue else { return }
            needsDisplay = true
        }
    }

    /// 柱与柱之间的间距（默认 8pt；额度页 25/31 桶时调小到 3pt 保证柱宽可读）
    var columnGap: CGFloat = 8 {
        didSet {
            guard columnGap != oldValue else { return }
            needsDisplay = true
        }
    }

    /// 数值行高度
    private static let valueRowHeight: CGFloat = 12
    /// 日期行高度
    private static let labelRowHeight: CGFloat = 12
    /// 单柱最大宽度（只有 1-2 天数据时不把整行撑满）
    private static let maxColumnWidth: CGFloat = 44
    /// 柱体区最大高度
    private static let barAreaHeight: CGFloat = 56

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.valueRowHeight + Self.barAreaHeight
                                    + Self.labelRowHeight + 8),
        ])
        setAccessibilityRole(.group)
        setAccessibilityLabel("近 6 日下行流量")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard !bars.isEmpty else { return }
        let count = CGFloat(bars.count)
        let available = max(1, (bounds.width - columnGap * (count - 1)) / count)
        let columnWidth = min(Self.maxColumnWidth, available)
        // 整体居中（少量数据时两侧留白，不贴着左边缘）
        let groupWidth = columnWidth * count + columnGap * (count - 1)
        let leftInset = max(0, (bounds.width - groupWidth) / 2)
        let barAreaTop = Self.valueRowHeight + 4
        let barBottom = barAreaTop + Self.barAreaHeight
        let ratios = MenuPanelMetrics.barRatios(values: bars.map(\.value))

        for (index, bar) in bars.enumerated() {
            let x = leftInset + CGFloat(index) * (columnWidth + columnGap)
            let centerX = x + columnWidth / 2

            // 数值（柱顶上方居中）
            let valueAttributes: [NSAttributedString.Key: Any] = [
                .font: MenuPanelStyle.smallValueFont,
                .foregroundColor: bar.isToday ? MenuPanelStyle.accentColor : NSColor.tertiaryLabelColor,
            ]
            let valueText = bar.valueText as NSString
            let valueSize = valueText.size(withAttributes: valueAttributes)
            // 贴边钳制：最右桶的数值文案不会被画布裁掉
            let valueX = min(max(0, centerX - valueSize.width / 2), max(0, bounds.width - valueSize.width))
            valueText.draw(at: NSPoint(x: valueX, y: 0), withAttributes: valueAttributes)

            // 柱体：相对最大值归一化，最小 2pt 保证「有数据就一定看得见」
            let ratio = ratios[index]
            let height = max(2, Self.barAreaHeight * CGFloat(ratio))
            let barRect = NSRect(x: x, y: barBottom - height, width: columnWidth, height: height)
            (bar.isToday ? MenuPanelStyle.accentColor : MenuPanelStyle.barColor).setFill()
            NSBezierPath(roundedRect: barRect, xRadius: 2, yRadius: 2).fill()

            // 日期（底部居中）
            let labelAttributes: [NSAttributedString.Key: Any] = [
                .font: MenuPanelStyle.smallValueFont,
                .foregroundColor: bar.isToday ? MenuPanelStyle.accentColor : NSColor.secondaryLabelColor,
            ]
            let label = bar.label as NSString
            let labelSize = label.size(withAttributes: labelAttributes)
            let labelX = min(max(0, centerX - labelSize.width / 2), max(0, bounds.width - labelSize.width))
            label.draw(at: NSPoint(x: labelX, y: barBottom + 6), withAttributes: labelAttributes)
        }
    }
}

// MARK: - 速率迷你折线（sparkline）

/// 速率趋势迷你折线 — 60 个 1 秒采样点，直接画折线（不引入图表库）
final class MenuPanelSparklineView: NSView {

    /// 采样值（越靠后越新）
    var values: [Double] = [] {
        didSet { needsDisplay = true }
    }

    /// 折线颜色（下行绿 / 上行橙）
    var lineColor: NSColor = MenuPanelStyle.downColor {
        didSet { needsDisplay = true }
    }

    init(lineColor: NSColor) {
        self.lineColor = lineColor
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 84),
            heightAnchor.constraint(equalToConstant: 20),
        ])
        setAccessibilityRole(.image)
        setAccessibilityLabel("速率趋势")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard values.count >= 2 else { return }
        let maxValue = values.max() ?? 0
        let inset: CGFloat = 1.5
        let width = bounds.width - inset * 2
        let height = bounds.height - inset * 2
        let step = width / CGFloat(values.count - 1)

        let path = NSBezierPath()
        path.lineWidth = 1.5
        path.lineJoinStyle = .round
        path.lineCapStyle = .round

        for (index, value) in values.enumerated() {
            // 最大值归一化为顶部；全 0 时贴中线，避免折线贴在底部看不见
            let normalized = maxValue > 0 ? value / maxValue : 0.5
            let point = NSPoint(x: inset + CGFloat(index) * step,
                                y: inset + height * CGFloat(1 - normalized))
            if index == 0 { path.move(to: point) } else { path.line(to: point) }
        }
        lineColor.setStroke()
        path.stroke()
    }
}
