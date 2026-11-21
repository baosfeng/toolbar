import AppKit
import NetworkMonitorDesign

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
        // 环的绘制只留一份（DrawnInk.ring）：自绘卡片复用同一个函数，两条路径不会画出两种环
        DrawnInk.ring(in: bounds, fraction: fraction, lineWidth: Self.ringWidth,
                      color: ringColor, track: SystemPalette.track)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.centerFont,
            .foregroundColor: textColor,
        ]
        let size = (centerText as NSString).size(withAttributes: attributes)
        (centerText as NSString).draw(at: NSPoint(x: bounds.midX - size.width / 2,
                                                  y: bounds.midY - size.height / 2),
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

    /// 单个分段（与自绘卡片共用同一个值类型，调用点写法不变）
    typealias Segment = SystemBarSegment

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
        // 绘制只留一份（SystemChartDrawing）：自绘卡片复用同一个函数，两条路径不会画出两种条
        SystemChartDrawing.drawStackedBar(segments: segments, total: total,
                                         pressureStroke: SystemChartDrawing.pressureStrokeColor(pressureLevel),
                                         gapColor: gapColor ?? SystemPalette.color(.cardMemory),
                                         in: bounds)
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
