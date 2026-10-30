import AppKit
import NetworkMonitorCore

// MARK: - 进程 Top-N 条形榜

/// 进程资源榜 — 名称 / 横向条形 / 数值，每行一条
///
/// **CPU 榜的条形用绝对 sqrt 刻度**：`sqrt(cpuPercent) × 13`（满条 = 100% = 占满一个核）。
/// 不能用「榜首归一化」——榜首一变全体按比例缩放，实测同一个 15.77% 的进程条长会在
/// 26%~197% 之间乱跳；绝对刻度下它恒为 51.6pt，波动 0。条长只由进程自身 CPU% 决定。
/// 版2 首屏只显示 Top-2（卡头「全部 ›」进 CPU 详情），内存榜按定稿不再出现在首屏。
final class SystemProcessListView: NSView {

    /// 单行数据（已按 CPU 占用排序）
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

    private var rowViews: [ProcessRowView] = []

    init(rows: Int = 3) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        for _ in 0..<max(1, rows) {
            rowViews.append(ProcessRowView())
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

    /// 更新榜单；rows 为空 = 不可得态（占位「—」，空条形）
    func update(_ rows: [Row], unavailableTip: String) {
        for (index, view) in rowViews.enumerated() {
            if index < rows.count {
                view.update(rows[index])
            } else {
                view.updateUnavailable(tip: unavailableTip)
            }
        }
    }

}

// MARK: - 行装配

extension SystemPaneView {

    /// 按维度构造进程榜行（首屏 Top-2 与「压力详情」Top-10 共用同一口径）
    static func processRows(_ snapshot: ProcessResourceSnapshot?,
                            metric: SystemProcessMetric,
                            limit: Int,
                            memoryTotal: UInt64?) -> [SystemProcessListView.Row] {
        SystemProcessBoard.rows(snapshot, metric: metric, limit: limit).map { usage in
            SystemProcessListView.Row(
                name: usage.name,
                fraction: SystemProcessBoard.barFraction(for: usage, metric: metric,
                                                        memoryTotal: memoryTotal),
                valueText: SystemProcessBoard.valueText(for: usage, metric: metric),
                isOver: metric == .cpu && usage.cpuPercent > 100,
                tip: SystemPaneTip.processRow(usage: usage, metric: metric,
                                              memoryTotal: memoryTotal))
        }
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
                                        color: SystemPalette.foregroundSecondary)
        barTrack = ProcessBarTrackView()
        valueLabel = MenuPanelLabel.text(SystemPaneFormat.placeholder,
                                         font: MenuPanelStyle.smallValueFont,
                                         color: SystemPalette.foregroundSecondary)
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
        nameLabel.textColor = SystemPalette.foregroundSecondary
        valueLabel.stringValue = row.valueText
        valueLabel.textColor = row.isOver ? SystemPaneStyle.processOverloaded
            : SystemPalette.foregroundSecondary
        // 必须显式退出空态：首屏 update(snapshot: nil) 已把行置为空态，
        // 不复位的话真实数据进来仍会画成空心描边条（条长看着永远是 0）
        barTrack.isEmptyState = false
        barTrack.isOver = row.isOver
        barTrack.fraction = row.fraction
        toolTip = row.tip
    }

    /// 不可得：占位「—」，空条形（描边 + 透明填充，与有数据的实心条明确区分）
    func updateUnavailable(tip: String) {
        nameLabel.stringValue = SystemPaneFormat.placeholder
        nameLabel.textColor = SystemPalette.meta
        valueLabel.stringValue = SystemPaneFormat.placeholder
        valueLabel.textColor = SystemPalette.meta
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
        SystemPalette.track.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()

        if isEmptyState {
            let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                       xRadius: radius, yRadius: radius)
            outline.lineWidth = 1
            SystemPalette.track.setStroke()
            outline.stroke()
            return
        }

        let value = fraction.isFinite ? min(1, max(0, fraction)) : 0
        guard value > 0 else { return }
        let fillRect = NSRect(x: bounds.minX, y: bounds.minY,
                              width: bounds.width * CGFloat(value), height: bounds.height)
        (isOver ? SystemPaneStyle.processOverloaded : SystemPalette.process).setFill()
        NSBezierPath(roundedRect: fillRect, xRadius: radius, yRadius: radius).fill()
    }
}
