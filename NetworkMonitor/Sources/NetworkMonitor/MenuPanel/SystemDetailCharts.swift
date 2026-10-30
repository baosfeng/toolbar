import AppKit

// MARK: - 详情页图表

/// 内存三段堆叠面积图 — wired / active / compressed 自下而上堆叠（占比口径，最大 100%）
///
/// 三段同属青绿族，靠明度阶梯区分；段与段之间不加描边（叠放时描边会互相割裂），
/// 只在最上沿补一条同族折线，读「总量走势」。
final class SystemStackedAreaChartView: NSView {

    var wiredValues: [Double] = [] { didSet { redrawIfChanged(oldValue, wiredValues) } }
    var activeValues: [Double] = [] { didSet { redrawIfChanged(oldValue, activeValues) } }
    var compressedValues: [Double] = [] { didSet { redrawIfChanged(oldValue, compressedValues) } }

    init(height: CGFloat = 40) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: height).isActive = true
        setAccessibilityRole(.image)
        setAccessibilityLabel("内存三段堆叠趋势")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let count = [wiredValues, activeValues, compressedValues].map(\.count).min() ?? 0
        guard count >= 2 else {
            SystemPalette.track.setFill()
            NSRect(x: bounds.minX, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
            return
        }
        let rect = bounds.insetBy(dx: 1, dy: 1)
        func series(_ values: [Double]) -> [Double] {
            values.suffix(count).map { $0.isFinite ? min(max($0, 0), 1) : 0 }
        }
        let wired = series(wiredValues)
        let active = series(activeValues)
        let compressed = series(compressedValues)
        let bottom = wired
        let middle = zip(wired, active).map { min(1, $0.0 + $0.1) }
        let top = zip(middle, compressed).map { min(1, $0.0 + $0.1) }
        let zeros = [Double](repeating: 0, count: count)

        func fill(lower: [Double], upper: [Double], color: NSColor) {
            color.setFill()
            SystemChartDrawing.bandPath(lower: lower, upper: upper, in: rect, maximum: 1).fill()
        }
        fill(lower: zeros, upper: bottom, color: SystemPalette.memoryWired)
        fill(lower: bottom, upper: middle, color: SystemPalette.memoryActive)
        fill(lower: middle, upper: top, color: SystemPalette.memoryCompressed)

        let line = SystemChartDrawing.linePath(values: top, in: rect, maximum: 1)
        line.lineWidth = 1
        SystemPalette.memoryWired.setStroke()
        line.stroke()
    }

    /// 只在真的变化时重绘（避免 5 秒刷新里三组序列重复置 needsDisplay）
    private func redrawIfChanged(_ oldValue: [Double], _ newValue: [Double]) {
        guard oldValue != newValue else { return }
        needsDisplay = true
    }
}

// MARK: - 磁盘读写双列

/// 读写速率双列 — 左读 / 右写，两列共用同一纵轴上限（高度可比），各自带同族渐变面积
///
/// 与首屏「单坐标系双线」画法不同：详情页高度足够，两列分开后每条曲线都能用满列高，
/// 也不会因为读的波峰把写的形状压平。
final class SystemIORatePairView: NSView {

    private let primaryColumn: SystemRateColumn
    private let secondaryColumn: SystemRateColumn

    init(height: CGFloat = 34) {
        primaryColumn = SystemRateColumn(label: "读", color: SystemPalette.diskRead, height: height)
        secondaryColumn = SystemRateColumn(label: "写", color: SystemPalette.diskWrite, height: height)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let row = NSStackView(views: [primaryColumn, secondaryColumn])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 12
        row.distribution = .fillEqually
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        setAccessibilityRole(.group)
        setAccessibilityLabel("磁盘读写速率双列")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 更新两列序列与数值文本（字节/秒；nil 文本由调用方给「—」）
    func update(primary: [Double], secondary: [Double],
                primaryText: String, secondaryText: String) {
        let maximum = max((primary + secondary).filter { $0.isFinite }.max() ?? 0, 0.000_001)
        primaryColumn.update(values: primary, maximum: maximum, valueText: primaryText)
        secondaryColumn.update(values: secondary, maximum: maximum, valueText: secondaryText)
    }
}

// MARK: - 单列

/// 速率单列 — 「读 / 写 + 数值」小标题 + 渐变面积折线
private final class SystemRateColumn: NSView {

    private let valueLabel: NSTextField
    private let sparkline: SystemSparklineView

    init(label: String, color: NSColor, height: CGFloat) {
        valueLabel = MenuPanelLabel.text(SystemPaneFormat.placeholder,
                                         font: SystemPaneStyle.microFont,
                                         color: SystemPalette.foregroundSecondary)
        sparkline = SystemSparklineView(lineColor: color, height: height)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let caption = MenuPanelLabel.text(label, font: SystemPaneStyle.tinyFont,
                                          color: SystemPalette.meta)
        let head = NSStackView(views: [caption, MenuPanelLabel.spacer(), valueLabel])
        head.orientation = .horizontal
        head.alignment = .firstBaseline
        head.spacing = 4
        let stack = NSStackView(views: [head, sparkline])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            head.widthAnchor.constraint(equalTo: stack.widthAnchor),
            sparkline.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 更新序列（共用纵轴上限）与数值
    func update(values: [Double], maximum: Double, valueText: String) {
        sparkline.fixedMaximum = maximum
        sparkline.values = values
        valueLabel.stringValue = valueText
    }
}
