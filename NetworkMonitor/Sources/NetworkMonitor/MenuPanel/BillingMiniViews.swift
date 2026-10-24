import AppKit

// MARK: - 细进度条

/// 3pt 细进度条 — 自绘填充，无子视图约束开销
///
/// 颜色按剩余比例分级：正常用强调色，剩余不足一半用橙色，不足两成用红色。
final class BillingProgressBarView: NSView {

    /// 告警级别
    enum Level {
        case normal
        case warn
        case danger
    }

    /// 条高（与原型 3pt 一致）
    static let preferredHeight: CGFloat = 3

    private var fraction: Double = 0
    private var level: Level = .normal

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Self.preferredHeight)
    }

    /// 更新剩余比例与告警级别
    func update(fraction: Double, level: Level) {
        self.fraction = min(max(fraction, 0), 1)
        self.level = level
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = max(bounds.height / 2, 1)
        NSColor.labelColor.withAlphaComponent(0.10).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        guard fraction > 0 else { return }
        let width = max(bounds.height, bounds.width * fraction)
        let fillRect = NSRect(x: 0, y: 0, width: width, height: bounds.height)
        fillColor.setFill()
        NSBezierPath(roundedRect: fillRect, xRadius: radius, yRadius: radius).fill()
    }

    private var fillColor: NSColor {
        switch level {
        case .normal: return .controlAccentColor
        case .warn:   return .systemOrange
        case .danger: return .systemRed
        }
    }
}

// MARK: - 迷你趋势

/// 22pt 迷你柱状趋势 — 收起态每个 provider 一条，最后一根高亮表示最近一个桶
///
/// 只画形状不画坐标轴，用 `draw` 直接渲染，避免几十个子视图参与布局。
final class BillingMiniTrendView: NSView {

    /// 固定高度（与原型一致）
    static let preferredHeight: CGFloat = 22

    private var values: [Double] = []

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Self.preferredHeight)
    }

    /// 更新分桶数值（顺序为时间正序）
    func update(values: [Double]) {
        self.values = values
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !values.isEmpty, bounds.width > 0 else { return }
        let gap: CGFloat = 1.5
        let count = values.count
        let barWidth = max(2, (bounds.width - gap * CGFloat(count - 1)) / CGFloat(count))
        let peak = values.max() ?? 0

        for (index, value) in values.enumerated() {
            let ratio = peak > 0 ? value / peak : 0
            let height = max(2, bounds.height * CGFloat(ratio))
            let x = CGFloat(index) * (barWidth + gap)
            let rect = NSRect(x: x, y: 0, width: barWidth, height: height)
            let isLast = index == count - 1
            let color = isLast
                ? NSColor.controlAccentColor
                : NSColor.labelColor.withAlphaComponent(0.26)
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5).fill()
        }
    }
}