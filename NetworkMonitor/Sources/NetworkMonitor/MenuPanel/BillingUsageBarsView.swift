import AppKit
import NetworkMonitorCore

// MARK: - 展开区主图（与 Token 页同一柱语法）

/// 用量柱图 —— 满高轨道 + 填充段，gap 2pt、圆角 2pt
///
/// 与 Token 页 `TokenBarsView` 同一语法：每列先画满高轨道（`trackColor`），
/// 再从底部叠填充段。改前是「柱 + 柱顶数值 + 日期标签」三行 88pt 的独立画法，
/// 与 Token 页的「轨道 + 段 + 轴 + 图例」并排就是两套图表语言。
/// 数值不再画在柱顶（25/31 桶时必然重叠），改由轴与图例承载 + 点击柱看 tooltip。
final class BillingUsageBarsView: NSView {

    /// 单桶数据
    struct Bucket {
        let value: Double
        let caption: String
    }

    private var buckets: [Bucket] = []
    private var fillColor: NSColor = PaneCardStyle.uncachedColor
    /// 当前悬停桶
    private var hoveredIndex: Int?
    private var trackingAreaRef: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityRole(.group)
        setAccessibilityLabel("用量柱状图")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func update(buckets: [Bucket], fillColor: NSColor) {
        self.buckets = buckets
        self.fillColor = fillColor
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !buckets.isEmpty else { return }
        let gap: CGFloat = 2
        let count = CGFloat(buckets.count)
        let columnWidth = max(1, (bounds.width - gap * (count - 1)) / count)
        let peak = max(buckets.map(\.value).max() ?? 0, 1)

        for (index, bucket) in buckets.enumerated() {
            let x = bounds.minX + CGFloat(index) * (columnWidth + gap)
            let column = NSRect(x: x, y: bounds.minY, width: columnWidth, height: bounds.height)
            PaneCardStyle.trackColor.setFill()
            NSBezierPath(roundedRect: column, xRadius: 2, yRadius: 2).fill()
            guard bucket.value > 0 else { continue }
            let height = max(1, bounds.height * CGFloat(bucket.value / peak))
            let rect = NSRect(x: x, y: bounds.minY, width: columnWidth, height: height)
            let isHovered = index == hoveredIndex
            (isHovered ? fillColor : fillColor.withAlphaComponent(0.92)).setFill()
            NSBezierPath(rect: rect).fill()
        }
    }

    // MARK: 悬停

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
        guard !buckets.isEmpty else { return }
        let point = convert(event.locationInWindow, from: nil)
        let gap: CGFloat = 2
        let count = CGFloat(buckets.count)
        let columnWidth = max(1, (bounds.width - gap * (count - 1)) / count)
        let index = Int(point.x / (columnWidth + gap))
        guard index >= 0, index < buckets.count else { return }
        hoveredIndex = index
        toolTip = buckets[index].caption
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hoveredIndex = nil
        toolTip = nil
        needsDisplay = true
    }

#if DEBUG
    /// 快照自证（仅 DEBUG）：强制悬停某根柱
    func forceHoverForSnapshot(_ index: Int?) {
        hoveredIndex = index
        toolTip = index.flatMap { buckets.indices.contains($0) ? buckets[$0].caption : nil }
        needsDisplay = true
    }
#endif
}
