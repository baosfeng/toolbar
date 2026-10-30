import AppKit
import NetworkMonitorCore

// MARK: - 进程 Top-N 条形榜

/// 进程资源榜 — 名称 / 横向条形 / 数值，每行一条
///
/// **CPU 榜的条形用绝对 sqrt 刻度**：`sqrt(cpuPercent) × 13`（满条 = 100% = 占满一个核）。
/// 不能用「榜首归一化」——榜首一变全体按比例缩放，实测同一个 15.77% 的进程条长会在
/// 26%~197% 之间乱跳；绝对刻度下它恒为 51.6pt，波动 0。条长只由进程自身 CPU% 决定。
/// 内存榜按「常驻 / 物理内存」线性百分比（量级集中，不需要压缩）。
final class SystemProcessListView: NSView {

    /// 榜单维度
    enum Metric {
        /// CPU 占用降序（条形 = sqrt 绝对刻度）
        case cpu
        /// 常驻内存降序（条形 = 常驻 / 物理内存）
        case memory

        /// 卡头标签（≤4 字）
        var title: String {
            switch self {
            case .cpu: return "CPU 榜"
            case .memory: return "内存榜"
            }
        }
    }
    /// 单行数据（已按当前榜单排序）
    struct Row: Equatable {
        /// 进程名（超宽截断显示，全名进 toolTip）
        let name: String
        /// 条形比例 0...1（已按榜单口径算好）
        let fraction: Double
        /// 右侧数值文本（原值，不做 clamp）
        let valueText: String
        /// 是否超量程（CPU > 100%，条形转琥珀）
        let isOver: Bool
        /// 悬停说明（含 pid 与完整口径）
        let tip: String
    }

    /// 展示行数（Top-3）
    private static let visibleRows = 3

    private var rowViews: [ProcessRowView] = []

    init(rows: Int = 3) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        for _ in 0..<max(1, rows) {
            let row = ProcessRowView()
            rowViews.append(row)
        }
        let stack = NSStackView(views: rowViews)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        for row in rowViews {
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        setAccessibilityRole(.group)
        setAccessibilityLabel("进程资源榜")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 更新榜单；rows 为空 = 不可得态（三行占位「—」，空条形）
    func update(_ rows: [Row], unavailableTip: String) {
        for (index, view) in rowViews.enumerated() {
            if index < rows.count {
                view.update(rows[index])
            } else {
                view.updateUnavailable(tip: unavailableTip)
            }
        }
    }

    // MARK: 刻度口径

    /// CPU 榜条形比例（绝对 sqrt 刻度）：`min(1, sqrt(cpuPercent) × 13 / 100)`
    ///
    /// 系数 13 的实测依据（见原型 §39）：27.6% → 68% 条长、10.7% → 43%、3% → 23%、1% → 13%。
    /// k=10 时榜首长态只有 52%，不够醒目；k=13 让常见区间都有足够权重，
    /// 同时 1% 的碎进程仍有 13% 可见。
    static func cpuBarFraction(_ cpuPercent: Double) -> Double {
        let raw = cpuPercent.isFinite ? max(0, cpuPercent) : 0
        return min(1, max(0, (raw.squareRoot() * 13) / 100))
    }

    /// 内存榜条形比例（线性）：常驻 / 物理内存
    static func memoryBarFraction(residentBytes: UInt64, totalBytes: UInt64) -> Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, Double(residentBytes) / Double(totalBytes))
    }

    /// CPU 榜数值文本：**原值不 clamp**（多线程可 >100%，削平会让排序失真）
    static func cpuValueText(_ cpuPercent: Double) -> String {
        guard cpuPercent.isFinite else { return SystemPaneFormat.placeholder }
        return String(format: "%.1f%%", max(0, cpuPercent))
    }
}

// MARK: - 单行

/// 进程行 — 名称（58pt）/ 条形（撑满）/ 数值（右对齐 34pt）
final class ProcessRowView: NSView {

    private let nameLabel: NSTextField
    private let barTrack: ProcessBarTrackView
    private let valueLabel: NSTextField

    init() {
        nameLabel = MenuPanelLabel.text(SystemPaneFormat.placeholder,
                                        font: SystemPaneStyle.microFont,
                                        color: MenuPanelStyle.secondaryText)
        barTrack = ProcessBarTrackView()
        valueLabel = MenuPanelLabel.text(SystemPaneFormat.placeholder,
                                         font: MenuPanelStyle.smallValueFont,
                                         color: MenuPanelStyle.secondaryText)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        valueLabel.alignment = .right
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let stack = NSStackView(views: [nameLabel, barTrack, valueLabel])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 13),
            nameLabel.widthAnchor.constraint(equalToConstant: 58),
            valueLabel.widthAnchor.constraint(equalToConstant: 34),
        ])
        setAccessibilityRole(.group)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 有数据
    func update(_ row: SystemProcessListView.Row) {
        nameLabel.stringValue = row.name
        nameLabel.textColor = MenuPanelStyle.secondaryText
        valueLabel.stringValue = row.valueText
        valueLabel.textColor = row.isOver ? SystemPaneStyle.processOverloaded : MenuPanelStyle.secondaryText
        // 必须显式退出空态：首屏 update(snapshot: nil) 已把行置为空态，
        // 不复位的话真实数据进来仍会画成空心描边条（条长看着永远是 0）
        barTrack.isEmptyState = false
        barTrack.isOver = row.isOver
        barTrack.fraction = row.fraction
        toolTip = row.tip
    }

    /// 不可得：三行占位，空条形（描边 + 透明填充，与有数据的实心条明确区分）
    func updateUnavailable(tip: String) {
        nameLabel.stringValue = SystemPaneFormat.placeholder
        nameLabel.textColor = MenuPanelStyle.tertiaryText
        valueLabel.stringValue = SystemPaneFormat.placeholder
        valueLabel.textColor = MenuPanelStyle.tertiaryText
        barTrack.fraction = 0
        barTrack.isEmptyState = true
        barTrack.isOver = false
        toolTip = tip
    }
}

// MARK: - 单条

/// 进程条形 — 5pt 高圆角轨道 + 实心填充；空态用 1pt 内描边占位
final class ProcessBarTrackView: NSView {

    /// 填充比例 0...1
    var fraction: Double = 0 {
        didSet {
            guard fraction != oldValue else { return }
            needsDisplay = true
        }
    }

    /// 超量程（CPU > 100%）→ 琥珀
    var isOver: Bool = false {
        didSet {
            guard isOver != oldValue else { return }
            needsDisplay = true
        }
    }

    /// 空态（不可得）：只画描边
    var isEmptyState: Bool = false {
        didSet {
            guard isEmptyState != oldValue else { return }
            needsDisplay = true
        }
    }

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 5).isActive = true
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        MenuPanelStyle.trackColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()

        if isEmptyState {
            let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                       xRadius: radius, yRadius: radius)
            outline.lineWidth = 1
            MenuPanelStyle.trackColor.setStroke()
            outline.stroke()
            return
        }

        let value = fraction.isFinite ? min(1, max(0, fraction)) : 0
        guard value > 0 else { return }
        let fillRect = NSRect(x: bounds.minX, y: bounds.minY,
                              width: bounds.width * CGFloat(value), height: bounds.height)
        (isOver ? SystemPaneStyle.processOverloaded : MenuPanelStyle.accentColor).setFill()
        NSBezierPath(roundedRect: fillRect, xRadius: radius, yRadius: radius).fill()
    }
}
