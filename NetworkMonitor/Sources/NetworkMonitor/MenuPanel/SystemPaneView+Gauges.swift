import AppKit

// MARK: - 每核柱阵

/// 每核占用柱阵 — P 核在前、E 核在后，用两级明度区分；悬停显示核号与占比
final class SystemCoreBarGridView: NSView {

    /// 每核数据（顺序即绘制顺序：P 核在前）
    var cores: [SystemCoreUsage] = [] {
        didSet {
            guard cores != oldValue else { return }
            hoveredIndex = nil
            needsDisplay = true
        }
    }

    private var hoveredIndex: Int?
    private var trackingAreaRef: NSTrackingArea?

    /// 柱与柱之间的间隙
    private static let columnGap: CGFloat = 2

    init(height: CGFloat = 44) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: height).isActive = true
        setAccessibilityRole(.image)
        setAccessibilityLabel("每核占用")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard !cores.isEmpty else {
            // 无核数据：只留一条底纹，不画柱（卡头已显示「—」）
            MenuPanelStyle.trackColor.setFill()
            NSRect(x: bounds.minX, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
            return
        }
        let width = columnWidth()
        let radius = min(1.5, width / 2)
        for (index, core) in cores.enumerated() {
            let x = CGFloat(index) * (width + Self.columnGap)
            MenuPanelStyle.trackColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: bounds.minY, width: width, height: bounds.height),
                         xRadius: radius, yRadius: radius).fill()

            let ratio = core.usage.isFinite ? min(1, max(0, core.usage)) : 0
            let fillHeight = max(1, bounds.height * CGFloat(ratio))
            let fill = NSRect(x: x, y: bounds.maxY - fillHeight, width: width, height: fillHeight)
            barColor(core: core, isHovered: index == hoveredIndex).setFill()
            NSBezierPath(roundedRect: fill, xRadius: radius, yRadius: radius).fill()
        }
        if let hoveredIndex, cores.indices.contains(hoveredIndex) {
            let core = cores[hoveredIndex]
            let centerX = CGFloat(hoveredIndex) * (width + Self.columnGap) + width / 2
            let percent = Int((min(1, max(0, core.usage)) * 100).rounded())
            SystemChartDrawing.drawTooltip("\(core.label) \(percent)%",
                                           centerX: centerX, topY: 0, within: bounds)
        }
    }

    /// 单列宽度（总宽扣掉间隙后等分）
    private func columnWidth() -> CGFloat {
        let count = CGFloat(cores.count)
        guard count > 0 else { return 0 }
        return max(1, (bounds.width - Self.columnGap * (count - 1)) / count)
    }

    /// P 核高对比、E 核低对比（同一强调色两级明度；悬停用满色强调）
    private func barColor(core: SystemCoreUsage, isHovered: Bool) -> NSColor {
        guard !isHovered else { return MenuPanelStyle.accentColor }
        // E 核 0.38 在浅色卡片上不足 2:1、看不清，提到 0.58 仍与 P 核（0.85）分得开
        return MenuPanelStyle.accentColor.withAlphaComponent(core.isPerformance ? 0.85 : 0.58)
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
        updateHover(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        guard hoveredIndex != nil else { return }
        hoveredIndex = nil
        needsDisplay = true
    }

    private func updateHover(at point: NSPoint) {
        guard !cores.isEmpty, bounds.contains(point) else {
            guard hoveredIndex != nil else { return }
            hoveredIndex = nil
            needsDisplay = true
            return
        }
        let width = columnWidth()
        let step = width + Self.columnGap
        let index = Int(max(0, point.x) / step)
        let startX = CGFloat(index) * step
        let newValue = (index < cores.count && point.x - startX <= width) ? index : nil
        guard newValue != hoveredIndex else { return }
        hoveredIndex = newValue
        needsDisplay = true
    }
}

// MARK: - 环形利用率

/// 环形利用率 — 中心显示百分比；空态显示「—」而不是隐藏整环
final class SystemRingView: NSView {

    /// 进度 0...1
    var fraction: Double = 0 {
        didSet {
            guard fraction != oldValue else { return }
            needsDisplay = true
        }
    }

    // 默认取项目强调色（与面板其它页同色系），调用方可覆盖
    var ringColor: NSColor = MenuPanelStyle.accentColor {
        didSet { needsDisplay = true }
    }

    /// 环心文字（通常是百分比）
    var centerText: String = "—" {
        didSet {
            guard centerText != oldValue else { return }
            needsDisplay = true
        }
    }

    private static let centerFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
    private static let ringWidth: CGFloat = 5

    init(diameter: CGFloat = 44) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: diameter),
            heightAnchor.constraint(equalToConstant: diameter),
        ])
        setAccessibilityRole(.image)
        setAccessibilityLabel("利用率环形")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let radius = max(1, (min(bounds.width, bounds.height) - Self.ringWidth) / 2)
        let center = NSPoint(x: bounds.midX, y: bounds.midY)

        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = Self.ringWidth
        MenuPanelStyle.trackColor.setStroke()
        track.stroke()

        let value = fraction.isFinite ? min(1, max(0, fraction)) : 0
        if value > 0 {
            let arc = NSBezierPath()
            arc.appendArc(withCenter: center, radius: radius, startAngle: 90,
                          endAngle: 90 - 360 * CGFloat(value), clockwise: true)
            arc.lineWidth = Self.ringWidth
            arc.lineCapStyle = .round
            ringColor.setStroke()
            arc.stroke()
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.centerFont,
            .foregroundColor: MenuPanelStyle.secondaryText,
        ]
        let size = (centerText as NSString).size(withAttributes: attributes)
        (centerText as NSString).draw(at: NSPoint(x: center.x - size.width / 2,
                                                  y: center.y - size.height / 2),
                                      withAttributes: attributes)
    }
}

// MARK: - 堆叠条

/// 分段堆叠条 — 按 `total` 归一化；圆角裁剪保证首尾圆润，段间不额外留缝
final class SystemStackedBarView: NSView {

    /// 单个分段
    struct Segment {
        /// 分段数值（与 `total` 同单位）
        let value: Double
        /// 分段颜色（语义色 + alpha）
        let color: NSColor
    }

    var segments: [Segment] = [] {
        didSet { needsDisplay = true }
    }

    /// 总量（≤0 时整条显示为轨道色，不崩）
    var total: Double = 0 {
        didSet {
            guard total != oldValue else { return }
            needsDisplay = true
        }
    }

    init(height: CGFloat = 8) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: height).isActive = true
        setAccessibilityRole(.image)
        setAccessibilityLabel("内存分段")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        let clipPath = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
        clipPath.addClip()
        MenuPanelStyle.trackColor.setFill()
        bounds.fill()

        guard total > 0, total.isFinite else { return }
        var x = bounds.minX
        for segment in segments {
            let ratio = segment.value.isFinite ? min(1, max(0, segment.value / total)) : 0
            let width = bounds.width * CGFloat(ratio)
            guard width > 0 else { continue }
            segment.color.setFill()
            NSRect(x: x, y: bounds.minY, width: width, height: bounds.height).fill()
            x += width
        }
    }
}

// MARK: - 压力徽标

/// 内存压力徽标 — 8pt 圆点：正常绿 / 警告黄 / 严重红（未知灰）
final class SystemPressureDotView: NSView {

    /// 压力级别（与 Core 三级枚举一一对应，未知态单独一档）
    enum Level {
        case normal
        case warning
        case critical
        case unknown
    }

    var level: Level = .unknown {
        didSet {
            guard level != oldValue else { return }
            needsDisplay = true
        }
    }

    init(size: CGFloat = 8) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size),
            heightAnchor.constraint(equalToConstant: size),
        ])
        setAccessibilityRole(.image)
        setAccessibilityLabel("内存压力")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let color: NSColor
        switch level {
        case .normal: color = .systemGreen
        case .warning: color = .systemYellow
        case .critical: color = .systemRed
        case .unknown: color = MenuPanelStyle.trackColor
        }
        color.setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5)).fill()
    }
}
