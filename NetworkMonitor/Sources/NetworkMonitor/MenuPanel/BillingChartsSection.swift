import AppKit
import NetworkMonitorCore
import NetworkMonitorDesign
import NetworkMonitorFeatureBilling
import NetworkMonitorUI

// MARK: - 图表区（页内唯一一条范围分段）

/// 图表区 —— 近 N 天柱图 + 模型 Top4 分布 + 30 天走势，共用页级唯一一条 24h/7d/30d 分段
///
/// 旧版是「每个 provider 的展开区各带一条分段 + 一套柱图」，切一次范围得逐家点；
/// v2 把分段提到页级：一条分段控制整块图表，数据由 BillingAggregate 跨 provider 汇总。
/// 图表高度不做压缩 —— 面板本来就会纵向滚动，用户口径是「宁可能滚，也别砍图」。
@MainActor
final class BillingChartsSectionView: NSView {

    /// 切换页级范围
    var onRangeChange: ((BillingRange) -> Void)?

    private let barCard = PaneCardBackgroundView()
    private let rangeSelector = BillingRangeSegmentedView()
    private let titleLabel = MenuPanelLabel.text("", font: PaneCardStyle.cardTitleFont,
                                                 color: PaneCardStyle.primaryText)
    private let subtitleLabel = MenuPanelLabel.text("", font: PaneCardStyle.metaFont,
                                                    color: PaneCardStyle.tertiaryText)
    private let barsView = BillingChartBarsView()
    private let axisRow = BillingAxisRow()
    private let emptyLabel = MenuPanelLabel.text("暂无用量数据", font: PaneCardStyle.metaFont,
                                                 color: PaneCardStyle.tertiaryText)

    private let modelCard = PaneCardBackgroundView()
    private let modelRows = BillingModelShareListView()

    private let trendCard = PaneCardBackgroundView()
    private let trendTitle = MenuPanelLabel.text("近 30 天走势", font: PaneCardStyle.cardTitleFont,
                                                 color: PaneCardStyle.primaryText)
    private let trendMeta = MenuPanelLabel.text("", font: PaneCardStyle.metaFont,
                                                color: PaneCardStyle.tertiaryText)
    private let trendView = BillingTrendLineView()

    /// 柱图高度（61 → 76pt：原 61 里还要塞卡头 / 轴行 / 3 × 3pt 间距，实绘仅约 40pt，
    /// 七根柱近乎方形；抬到 76 后实绘约 55pt，柱高:柱宽 ≈ 2:1，才读得出「柱状图」）
    ///
    /// 额度页本来就允许纵向滚动（面板根视图是 NSScrollView），加高不裁切内容。
    static let barHeight: CGFloat = 76
    /// 走势高度（30 个折线点，比柱图矮一档）
    static let trendHeight: CGFloat = 34

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false

        rangeSelector.onSelect = { [weak self] range in self?.onRangeChange?(range) }

        let headRow = NSStackView(views: [titleLabel, subtitleLabel,
                                          MenuPanelLabel.spacer(), rangeSelector])
        headRow.orientation = .horizontal
        headRow.alignment = .centerY
        headRow.spacing = 5
        // 标题先占位：静息「近 7 天请求」不能被副标挤成「近 7 天…」（副标是补充信息，可截断）
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        rangeSelector.setContentHuggingPriority(.required, for: .horizontal)
        rangeSelector.setContentCompressionResistancePriority(.required, for: .horizontal)

        barsView.heightAnchor.constraint(equalToConstant: Self.barHeight).isActive = true
        emptyLabel.isHidden = true

        let barBody = NSStackView(views: [headRow, barsView, axisRow, emptyLabel])
        barBody.orientation = .vertical
        barBody.alignment = .leading
        barBody.spacing = 3
        barBody.translatesAutoresizingMaskIntoConstraints = false
        barCard.translatesAutoresizingMaskIntoConstraints = false
        barCard.addSubview(barBody)
        NSLayoutConstraint.activate([
            barBody.leadingAnchor.constraint(equalTo: barCard.contentView.leadingAnchor),
            barBody.trailingAnchor.constraint(equalTo: barCard.contentView.trailingAnchor),
            barBody.topAnchor.constraint(equalTo: barCard.contentView.topAnchor),
            barBody.bottomAnchor.constraint(equalTo: barCard.contentView.bottomAnchor),
        ])
        for view in barBody.arrangedSubviews {
            view.widthAnchor.constraint(equalTo: barBody.widthAnchor).isActive = true
        }

        modelCard.translatesAutoresizingMaskIntoConstraints = false
        modelRows.translatesAutoresizingMaskIntoConstraints = false
        modelCard.addSubview(modelRows)
        NSLayoutConstraint.activate([
            modelRows.leadingAnchor.constraint(equalTo: modelCard.contentView.leadingAnchor),
            modelRows.trailingAnchor.constraint(equalTo: modelCard.contentView.trailingAnchor),
            modelRows.topAnchor.constraint(equalTo: modelCard.contentView.topAnchor),
            modelRows.bottomAnchor.constraint(equalTo: modelCard.contentView.bottomAnchor),
        ])

        trendView.heightAnchor.constraint(equalToConstant: Self.trendHeight).isActive = true
        let trendHead = NSStackView(views: [trendTitle, MenuPanelLabel.spacer(), trendMeta])
        trendHead.orientation = .horizontal
        trendHead.alignment = .firstBaseline
        trendHead.spacing = 5
        let trendBody = NSStackView(views: [trendHead, trendView])
        trendBody.orientation = .vertical
        trendBody.alignment = .leading
        trendBody.spacing = 2
        trendBody.translatesAutoresizingMaskIntoConstraints = false
        trendCard.translatesAutoresizingMaskIntoConstraints = false
        trendCard.addSubview(trendBody)
        NSLayoutConstraint.activate([
            trendBody.leadingAnchor.constraint(equalTo: trendCard.contentView.leadingAnchor),
            trendBody.trailingAnchor.constraint(equalTo: trendCard.contentView.trailingAnchor),
            trendBody.topAnchor.constraint(equalTo: trendCard.contentView.topAnchor),
            trendBody.bottomAnchor.constraint(equalTo: trendCard.contentView.bottomAnchor),
        ])
        for view in trendBody.arrangedSubviews {
            view.widthAnchor.constraint(equalTo: trendBody.widthAnchor).isActive = true
        }

        let root = NSStackView(views: [barCard, modelCard, trendCard])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = PaneCardStyle.cardSpacing
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor),
            root.trailingAnchor.constraint(equalTo: trailingAnchor),
            root.topAnchor.constraint(equalTo: topAnchor),
            root.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        for view in root.arrangedSubviews {
            view.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        }
        setAccessibilityRole(.group)
        setAccessibilityLabel("额度用量图表")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 键盘可达行：范围分段的三个按钮
    var focusableRows: [MenuPanelRow] { rangeSelector.focusableRows }

    // MARK: - 数据更新

    /// 应用一帧数据
    ///
    /// - Parameters:
    ///   - states: 可见 provider 的运行时状态（图表数据从它们的 usage 汇总）
    ///   - range: 页级当前范围
    func update(states: [BillingMonitor.ProviderState], range: BillingRange) {
        rangeSelector.update(ranges: BillingRange.allCases, selected: range)
        let usages = states.compactMap(\.usage)
        let series = BillingChartAggregate.chart(usages: usages, range: range)

        titleLabel.stringValue = Self.barTitle(range)
        // 标题行只放合计：完整口径（含日均）进 tooltip，否则会把标题挤成「近 7 天…」
        subtitleLabel.stringValue = BillingChartAggregate.chartTotalLabel(series)
        subtitleLabel.toolTip = BillingChartAggregate.chartSubtitle(series, range: range)
        barsView.isHidden = series.isEmpty
        axisRow.isHidden = series.isEmpty
        emptyLabel.isHidden = !series.isEmpty
        // 空序列分两种：真没数据 / 正在按页级范围补拉（首帧 provider 还停在 24h 时，
        // 写「暂无用量数据」会让用户以为这段时间真没用量）
        emptyLabel.stringValue = Self.emptyChartText(states: states, range: range)
        if !series.isEmpty {
            barsView.update(points: series.points,
                            metric: series.metric,
                            granularity: BillingChartAggregate.granularity(for: range),
                            fillColor: Self.barColor(series.metric))
            axisRow.update(left: Self.axisLeft(series.points.first?.label ?? "", range: range),
                           right: Self.axisRight(range))
        }

        modelRows.update(models: BillingChartAggregate.topModels(usages: usages, range: range))
        modelCard.isHidden = modelRows.isEmpty

        // 走势卡：拿到 30 天数据就画 30 天（与上方分段解耦，切到 24h 也看得见长期趋势）；
        // 只有当前范围的数据时退回当前范围并改标题——口径与标题必须一致，不能谎报「近 30 天」
        let month = BillingChartAggregate.chart(usages: usages, range: .last30Days)
        let trend = month.isEmpty ? series : month
        let trendRange: BillingRange = month.isEmpty ? range : .last30Days
        trendTitle.stringValue = Self.trendTitle(trendRange)
        trendView.update(points: trend.points)
        trendMeta.stringValue = trend.isEmpty ? "暂无数据"
            : BillingChartAggregate.chartSubtitle(trend, range: trendRange)
        trendCard.isHidden = trend.isEmpty
    }

    // MARK: - 文案与配色

    /// 柱图标题随范围变化
    static func barTitle(_ range: BillingRange) -> String {
        switch range {
        case .last24Hours: return "近 24 小时"
        case .last7Days: return "近 7 天"
        case .last30Days: return "近 30 天"
        }
    }

    /// 走势卡标题（随数据口径变化）
    static func trendTitle(_ range: BillingRange) -> String {
        switch range {
        case .last24Hours: return "近 24 小时走势"
        case .last7Days: return "近 7 天走势"
        case .last30Days: return "近 30 天走势"
        }
    }

    /// 柱图空态文案（真的没数据 vs 正在按页级范围补拉）
    static func emptyChartText(states: [BillingMonitor.ProviderState],
                               range: BillingRange) -> String {
        let candidates = states.map {
            BillingRangeAlignment.Candidate(id: $0.descriptor.id,
                                            supportsUsage: $0.descriptor.supportsUsage,
                                            supportedRanges: $0.descriptor.supportedRanges,
                                            currentRange: $0.range)
        }
        let aligning = !BillingRangeAlignment.idsNeedingAlignment(candidates, pageRange: range).isEmpty
        let loading = states.contains { $0.descriptor.supportsUsage && $0.isLoading }
        return (aligning || loading) ? "统计中…" : "暂无用量数据"
    }

    /// 轴左侧标签（首桶读数 + 粒度单位）
    ///
    /// 改造前只给裸数字「14」，7d / 30d 下读不出那 14 是日还是时；补单位后与悬停文案
    /// （「14 时 · 1,204」）同一粒度口径，两处不再各写一套。
    static func axisLeft(_ label: String, range: BillingRange) -> String {
        guard !label.isEmpty else { return label }
        let unit = BillingChartGeometry.captionUnit(for: BillingChartAggregate.granularity(for: range))
        return label + " " + unit
    }

    /// 轴右侧标签（与旧展开区同一口径，避免两处写法不同）
    static func axisRight(_ range: BillingRange) -> String {
        range == .last24Hours ? "现在" : "今天"
    }

    /// 柱色：请求数用族 1 色、金额用正常墨色（与改造前展开区同源）
    static func barColor(_ metric: BillingChartAggregate.Metric) -> NSColor {
        switch metric {
        case .requests: return PaneCardStyle.uncachedColor
        case .spend: return PaneCardStyle.okColor
        }
    }
}
