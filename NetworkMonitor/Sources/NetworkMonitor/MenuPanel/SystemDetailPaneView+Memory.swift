import AppKit
import NetworkMonitorCore

// MARK: - 内存详情页

/// 内存详情 — 已用/总量（28pt）+ 压力徽标 + 四段条与四段数值占比 + 60 秒三段堆叠 + 交换
///
/// 首屏下沉回这里的是四段数值行（内核 / 活跃 / 压缩 / 空闲的 GB 数与占比）与换出量；
/// 深色下三段明度阶梯反向（wired 最亮），数值文字统一走 `memoryInk`，不染成段色。
final class SystemMemoryDetailView: NSView {

    private let hero = SystemMetricValueView(fontSize: 28, unitFontSize: 10)
    private let subtitle: NSTextField
    private let badge = SystemPressureBadgeView()
    private let stackCard: SystemDetailCardView
    private let bar = SystemStackedBarView(height: 12)
    private let splitFacts = SystemDetailFactGrid(rows: 4)
    private let trendCard: SystemDetailCardView
    private let trend = SystemStackedAreaChartView(height: 40)
    private let factsCard: SystemDetailCardView
    private let facts = SystemDetailFactGrid(rows: 4)

    init() {
        let wash = SystemPalette.wash(.memory)
        subtitle = MenuPanelLabel.text("",
                                       font: NSFont.systemFont(ofSize: 9, weight: .semibold),
                                       color: SystemPalette.meta)
        stackCard = SystemDetailCardView(wash: wash)
        trendCard = SystemDetailCardView(title: "近 60 秒堆叠",
                                         meta: "wired → active → compressed", wash: wash)
        factsCard = SystemDetailCardView(wash: wash)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        bar.gapColor = wash
        stackCard.addContent(bar)
        stackCard.addContent(splitFacts)
        trendCard.addContent(trend)
        factsCard.addContent(facts)

        subtitle.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let subRow = NSStackView(views: [subtitle, badge, MenuPanelLabel.spacer()])
        subRow.orientation = .horizontal
        subRow.alignment = .centerY
        subRow.spacing = 6

        let stack = NSStackView(views: [hero, subRow, stackCard, trendCard, factsCard])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            subRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        for view in [stackCard, trendCard, factsCard] {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        setAccessibilityRole(.group)
        setAccessibilityLabel("内存详情")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 刷新
    func update(_ context: SystemDetailContext) {
        guard let memory = context.snapshot?.memory, memory.total > 0 else {
            hero.reset(color: SystemPalette.meta)
            subtitle.stringValue = "已用 = 内核 + 活跃 + 压缩 ÷ 物理内存 · 读数不可得"
            badge.update(.unknown)
            bar.segments = []
            bar.total = 0
            splitFacts.update(unavailableSegmentFacts(), keyColor: SystemPalette.memoryInk)
            trend.wiredValues = []
            trend.activeValues = []
            trend.compressedValues = []
            facts.update(unavailableFacts(), keyColor: SystemPalette.memoryInk)
            return
        }
        let total = Double(memory.total)
        let used = min(Double(memory.used), total)
        let wired = min(Double(memory.wired), used)
        let compressed = min(Double(memory.compressed), max(0, used - wired))
        let active = max(0, used - wired - compressed)
        let free = max(0, total - used)

        hero.update(value: SystemDetailFormatting.gigabyteValueText(memory.used),
                    color: SystemPalette.memoryInk,
                    unit: "GB / " + SystemDetailFormatting.byteCountText(memory.total))
        subtitle.stringValue = "已用 = 内核 + 活跃 + 压缩 ÷ 物理内存 · "
            + SystemDetailFormatting.compactPercentText(used / total)

        bar.total = total
        bar.segments = [
            .init(value: wired, color: SystemPaneStyle.memoryWired),
            .init(value: active, color: SystemPaneStyle.memoryActive),
            .init(value: compressed, color: SystemPaneStyle.memoryCompressed),
            .init(value: free, color: .clear),
        ]
        let level = SystemPaneView.level(for: memory.pressure)
        bar.pressureLevel = level
        badge.update(level)

        func segment(_ bytes: Double) -> String {
            SystemDetailFormatting.gigabyteValueText(UInt64(max(0, bytes)))
        }
        func share(_ bytes: Double) -> String {
            SystemDetailFormatting.sharePercentText(part: UInt64(max(0, bytes)),
                                                    total: memory.total)
        }
        splitFacts.update([
            .init(label: "内核", value: segment(wired), unit: "GB · \(share(wired))", isKey: false),
            .init(label: "活跃", value: segment(active), unit: "GB · \(share(active))", isKey: false),
            .init(label: "压缩", value: segment(compressed), unit: "GB · \(share(compressed))",
                  isKey: false),
            .init(label: "空闲", value: segment(free), unit: "GB · \(share(free))", isKey: false),
        ], keyColor: SystemPalette.memoryInk)

        trend.wiredValues = context.memoryWiredHistory
        trend.activeValues = context.memoryActiveHistory
        trend.compressedValues = context.memoryCompressedHistory

        facts.update([
            .init(label: "交换", value: SystemDetailFormatting.byteCountText(memory.swapUsed),
                  unit: nil, isKey: true),
            .init(label: "压力等级", value: Self.pressureText(memory.pressure), unit: nil,
                  isKey: false),
            .init(label: "物理内存",
                  value: SystemDetailFormatting.byteCountText(memory.total), unit: nil,
                  isKey: false),
            .init(label: "已用", value: SystemDetailFormatting.byteCountText(memory.used),
                  unit: nil, isKey: false),
        ], keyColor: SystemPalette.memoryInk)
    }

    /// 压力等级文案
    static func pressureText(_ pressure: MemoryPressureLevel) -> String {
        switch pressure {
        case .normal: return "正常"
        case .warning: return "警示"
        case .critical: return "严重"
        }
    }

    private func unavailableSegmentFacts() -> [SystemDetailFactGrid.Item] {
        ["内核", "活跃", "压缩", "空闲"].map {
            .init(label: $0, value: SystemPaneFormat.placeholder, unit: nil, isKey: false)
        }
    }

    private func unavailableFacts() -> [SystemDetailFactGrid.Item] {
        [("交换", true), ("压力等级", false), ("物理内存", false), ("已用", false)].map {
            .init(label: $0.0, value: SystemPaneFormat.placeholder, unit: nil, isKey: $0.1)
        }
    }
}
