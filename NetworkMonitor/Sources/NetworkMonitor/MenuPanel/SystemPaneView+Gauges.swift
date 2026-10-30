import AppKit

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

    /// 环色（GPU 族靛 / 电池绿等，调用方可覆盖）
    var ringColor: NSColor = SystemPalette.gpu {
        didSet { needsDisplay = true }
    }

    /// 环心文字颜色（数值走 ink 变体）
    var textColor: NSColor = SystemPalette.gpuInk {
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
        SystemPalette.track.setStroke()
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
            .foregroundColor: textColor,
        ]
        let size = (centerText as NSString).size(withAttributes: attributes)
        (centerText as NSString).draw(at: NSPoint(x: center.x - size.width / 2,
                                                  y: center.y - size.height / 2),
                                      withAttributes: attributes)
    }
}

// MARK: - 堆叠条

/// 分段堆叠条 — 按 `total` 归一化；圆角裁剪保证首尾圆润，段间留 0.5pt 卡底色缝便于分段识别
///
/// 内存卡用四段：wired / active / compressed 三段实色 + free 段传 `NSColor.clear`
/// （留空露出轨道底色，即「空闲」），四段之和等于物理内存总量。
/// 压力态（警告 / 紧张）额外给整条轨道 1pt 内描边：只靠卡头徽标时，
/// 视线落在条形上根本看不出「紧张」。
final class SystemStackedBarView: NSView {

    /// 单个分段
    struct Segment {
        /// 分段数值（与 `total` 同单位）
        let value: Double
        /// 分段颜色（语义色；传 `.clear` 表示该段留空）
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

    /// 压力态轨道描边级别（normal 不描边）
    var pressureLevel: SystemPressureDotView.Level = .normal {
        didSet {
            guard pressureLevel != oldValue else { return }
            needsDisplay = true
        }
    }

    /// 段间缝隙颜色（nil 时取内存卡 wash：缝是「卡底透出来」，不是轨道灰）
    var gapColor: NSColor? {
        didSet { needsDisplay = true }
    }

    /// 段间缝隙宽度
    private static let segmentGap: CGFloat = 0.5

    init(height: CGFloat = 9) {
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
        let clipPath = NSBezierPath(roundedRect: bounds, xRadius: 2, yRadius: 2)
        clipPath.addClip()
        SystemPalette.track.setFill()
        bounds.fill()

        guard total > 0, total.isFinite else {
            drawPressureStroke()
            return
        }
        let visible = segments.filter { $0.value.isFinite && $0.value > 0 }
        guard !visible.isEmpty else {
            drawPressureStroke()
            return
        }
        var x = bounds.minX
        for (index, segment) in visible.enumerated() {
            let ratio = min(1, max(0, segment.value / total))
            let width = bounds.width * CGFloat(ratio)
            segment.color.setFill()
            NSRect(x: x, y: bounds.minY, width: width, height: bounds.height).fill()
            // 段间缝：在边界处压一条卡底色细线（首段左侧与末段右侧不画）
            if index < visible.count - 1 {
                (gapColor ?? SystemPalette.color(.cardMemory)).setFill()
                NSRect(x: x + width - Self.segmentGap, y: bounds.minY,
                       width: Self.segmentGap, height: bounds.height).fill()
            }
            x += width
        }
        drawPressureStroke()
    }

    /// 压力态内描边 — 1pt 沿轨道内侧，不遮四段色块（内缩半线宽避免被裁切）
    private func drawPressureStroke() {
        guard let color = pressureStrokeColor else { return }
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
        path.lineWidth = 1
        color.setStroke()
        path.stroke()
    }

    /// 压力等级 → 描边色（正常 / 未知不描边，语义与卡头圆点一致）
    private var pressureStrokeColor: NSColor? {
        switch pressureLevel {
        case .warning: return SystemPalette.warn
        case .critical: return SystemPalette.danger
        case .normal, .unknown: return nil
        }
    }
}

// MARK: - 压力徽标

/// 内存压力徽标 — 8pt 圆点：正常绿 / 警告琥珀 / 严重红（未知灰）
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
        case .normal: color = SystemPalette.ok
        case .warning: color = SystemPalette.warn
        case .critical: color = SystemPalette.danger
        case .unknown: color = SystemPalette.track
        }
        color.setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5)).fill()
    }
}
