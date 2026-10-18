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
        /// 悬停提示文案（如 "22:00–23:00 · 302 次"）；nil 时回退到 valueText
        let detail: String?

        init(label: String, value: UInt64, valueText: String, isToday: Bool, detail: String? = nil) {
            self.label = label
            self.value = value
            self.valueText = valueText
            self.isToday = isToday
            self.detail = detail
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

    /// 当前悬停柱下标（nil = 未悬停）
    private var hoveredIndex: Int?
    private var trackingAreaRef: NSTrackingArea?

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
        let layout = columnLayout(for: bars.count)
        let barAreaTop = Self.valueRowHeight + 4
        let barBottom = barAreaTop + Self.barAreaHeight
        let ratios = MenuPanelMetrics.barRatios(values: bars.map(\.value))

        for (index, bar) in bars.enumerated() {
            let x = layout.leftInset + CGFloat(index) * (layout.width + columnGap)
            let centerX = x + layout.width / 2
            let isHovered = index == hoveredIndex

            // 数值（柱顶上方居中；悬停柱也显示）
            let valueAttributes: [NSAttributedString.Key: Any] = [
                .font: MenuPanelStyle.smallValueFont,
                .foregroundColor: (bar.isToday || isHovered)
                    ? MenuPanelStyle.accentColor : NSColor.tertiaryLabelColor,
            ]
            let valueText = bar.valueText as NSString
            let valueSize = valueText.size(withAttributes: valueAttributes)
            // 贴边钳制：最右桶的数值文案不会被画布裁掉
            let valueX = min(max(0, centerX - valueSize.width / 2), max(0, bounds.width - valueSize.width))
            valueText.draw(at: NSPoint(x: valueX, y: 0), withAttributes: valueAttributes)

            // 柱体：相对最大值归一化，最小 2pt 保证「有数据就一定看得见」；悬停柱用强调色
            let ratio = ratios[index]
            let height = max(2, Self.barAreaHeight * CGFloat(ratio))
            let barRect = NSRect(x: x, y: barBottom - height, width: layout.width, height: height)
            // 悬停柱用满色强调，今天用 75% 强调色，普通柱 24% 前景色
            let fillColor: NSColor = isHovered
                ? MenuPanelStyle.accentColor
                : (bar.isToday ? MenuPanelStyle.accentColor.withAlphaComponent(0.75) : MenuPanelStyle.barColor)
            fillColor.setFill()
            NSBezierPath(roundedRect: barRect, xRadius: 2, yRadius: 2).fill()

            // 日期（底部居中）
            let labelAttributes: [NSAttributedString.Key: Any] = [
                .font: MenuPanelStyle.smallValueFont,
                .foregroundColor: (bar.isToday || isHovered)
                    ? MenuPanelStyle.accentColor : NSColor.secondaryLabelColor,
            ]
            let label = bar.label as NSString
            let labelSize = label.size(withAttributes: labelAttributes)
            let labelX = min(max(0, centerX - labelSize.width / 2), max(0, bounds.width - labelSize.width))
            label.draw(at: NSPoint(x: labelX, y: barBottom + 6), withAttributes: labelAttributes)
        }

        // 悬停提示气泡最后绘制，保证盖在柱体与数值之上
        if let hoveredIndex, bars.indices.contains(hoveredIndex) {
            let bar = bars[hoveredIndex]
            if let detail = bar.detail ?? (bar.valueText.isEmpty ? nil : bar.valueText) {
                drawTooltip(detail, barIndex: hoveredIndex, layout: layout,
                            barBottom: barBottom, ratios: ratios)
            }
        }
    }

    // MARK: - 悬停交互

    /// 柱布局（宽 + 左侧留白），draw 与命中测试共用
    private func columnLayout(for count: Int) -> (width: CGFloat, leftInset: CGFloat) {
        let n = CGFloat(count)
        let available = max(1, (bounds.width - columnGap * (n - 1)) / n)
        let width = min(Self.maxColumnWidth, available)
        let groupWidth = width * n + columnGap * (n - 1)
        return (width, max(0, (bounds.width - groupWidth) / 2))
    }

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
        updateHover(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        guard hoveredIndex != nil else { return }
        hoveredIndex = nil
        needsDisplay = true
    }

    /// 命中测试：落在柱体区（数值行以下）且在该柱宽度内才高亮
    private func updateHover(at point: NSPoint) {
        guard !bars.isEmpty, bounds.contains(point), point.y >= Self.valueRowHeight else {
            guard hoveredIndex != nil else { return }
            hoveredIndex = nil
            needsDisplay = true
            return
        }
        let layout = columnLayout(for: bars.count)
        let step = layout.width + columnGap
        let index = Int((point.x - layout.leftInset) / step)
        let columnStart = layout.leftInset + CGFloat(index) * step
        let inColumn = index >= 0 && index < bars.count
            && point.x >= columnStart && point.x <= columnStart + layout.width
        let newValue = inColumn ? index : nil
        guard newValue != hoveredIndex else { return }
        hoveredIndex = newValue
        needsDisplay = true
    }

#if DEBUG
    /// 快照自证专用（仅 DEBUG）：强制悬停某根柱，用于渲染 tooltip 取证
    func forceHoverForSnapshot(_ index: Int?) {
        hoveredIndex = index
        needsDisplay = true
    }
#endif

    /// 悬停气泡：深色底 + 反色文字，贴边自动钳制
    private func drawTooltip(_ text: String, barIndex: Int,
                             layout: (width: CGFloat, leftInset: CGFloat),
                             barBottom: CGFloat, ratios: [Double]) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: MenuPanelStyle.smallValueFont,
            .foregroundColor: NSColor.windowBackgroundColor,
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let padding: CGFloat = 4
        let width = textSize.width + padding * 2
        let height = textSize.height + 2
        let centerX = layout.leftInset + CGFloat(barIndex) * (layout.width + columnGap) + layout.width / 2
        let barHeight = max(2, Self.barAreaHeight * CGFloat(ratios[barIndex]))
        let barTop = barBottom - barHeight
        let x = min(max(0, centerX - width / 2), max(0, bounds.width - width))
        let y = max(0, barTop - height - 4)
        let rect = NSRect(x: x, y: y, width: width, height: height)
        MenuPanelStyle.dynamicLabel(alpha: 0.92).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
        (text as NSString).draw(at: NSPoint(x: rect.minX + padding, y: rect.minY + 1),
                                withAttributes: attributes)
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
