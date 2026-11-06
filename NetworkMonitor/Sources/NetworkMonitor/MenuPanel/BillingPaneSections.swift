import AppKit
import NetworkMonitorCore

// MARK: - 用量区（展开后）

/// 用量区 —— 表头（「用量」+ 范围分段）→ 指标行 → 柱图 + 轴 + 图例 → 模型 Top3
///
/// 与 Token 页的图表卡同一语法：柱图用 `BillingUsageBarsView`（满高轨道 + 段），
/// 下方一行轴（首桶时间 / 现在）、一行图例（色块 + 数值），模型明细与 Token 的分布行同一排法。
final class BillingUsageSectionView: NSView {

    /// 切换时间范围
    var onRangeChange: ((BillingRange) -> Void)?

    private let rangeSelector = BillingRangeSegmentedView()
    private let headerRow = NSStackView()
    /// 明细缺失说明入口（悬停提示；正常数据下隐藏）
    private let metricHintButton = NSButton()
    private let metricsLine = BillingUsageSectionView.makeLineLabel()
    private let barsView = BillingUsageBarsView()
    private let axisRow = BillingAxisRow()
    private let legendRow = NSStackView()
    private let divider = BillingDividerView()
    private let modelsHeader = NSStackView()
    private let modelsTitle = MenuPanelLabel.text("按模型", font: PaneCardStyle.cardTitleFont,
                                                color: PaneCardStyle.secondaryText)
    private let modelsTrailing = MenuPanelLabel.text("", font: PaneCardStyle.metaFont,
                                                     color: PaneCardStyle.tertiaryText)
    private let modelStack = NSStackView()
    private var modelRows: [BillingModelRow] = []
    private var modelsSignature = ""

    // MARK: - 初始化

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        rangeSelector.onSelect = { [weak self] range in self?.onRangeChange?(range) }

        let usageTitle = MenuPanelLabel.text("用量", font: PaneCardStyle.cardTitleFont,
                                             color: PaneCardStyle.secondaryText)
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 6
        metricHintButton.image = NSImage(systemSymbolName: "questionmark.circle",
                                         accessibilityDescription: "用量明细说明")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .regular))
        metricHintButton.isBordered = false
        metricHintButton.bezelStyle = .inline
        metricHintButton.contentTintColor = PaneCardStyle.secondaryText
        metricHintButton.toolTip = "该计划仅返回请求数，不提供金额与 token 明细"
        metricHintButton.setAccessibilityLabel("用量明细说明")
        metricHintButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            metricHintButton.widthAnchor.constraint(equalToConstant: 14),
            metricHintButton.heightAnchor.constraint(equalToConstant: 14),
        ])
        metricHintButton.isHidden = true

        headerRow.addArrangedSubview(usageTitle)
        headerRow.addArrangedSubview(MenuPanelLabel.spacer())
        headerRow.addArrangedSubview(metricHintButton)
        headerRow.addArrangedSubview(rangeSelector)

        // 柱高与 Token 首屏主图同一档（22pt）；桶数多时不至于把柱压到 1pt 以下
        barsView.heightAnchor.constraint(
            equalToConstant: PaneCardStyle.bucketChartHeight * 2).isActive = true

        legendRow.orientation = .horizontal
        legendRow.alignment = .centerY
        legendRow.spacing = 10

        modelsHeader.orientation = .horizontal
        modelsHeader.alignment = .firstBaseline
        modelsHeader.spacing = 6
        modelsTrailing.setContentHuggingPriority(.required, for: .horizontal)
        modelsTrailing.alignment = .right
        modelsHeader.addArrangedSubview(modelsTitle)
        modelsHeader.addArrangedSubview(MenuPanelLabel.spacer())
        modelsHeader.addArrangedSubview(modelsTrailing)

        modelStack.orientation = .vertical
        modelStack.alignment = .leading
        modelStack.spacing = PaneCardStyle.rowSpacing
        modelStack.isHidden = true
        modelsHeader.isHidden = true
        divider.isHidden = true
        legendRow.isHidden = true

        let stack = NSStackView(views: [headerRow, metricsLine, barsView, axisRow,
                                        legendRow, divider, modelsHeader, modelStack])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        for view in stack.arrangedSubviews {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    var focusableRows: [MenuPanelRow] { rangeSelector.focusableRows }

    // MARK: - 数据更新

    func update(usage: BillingUsage?, range: BillingRange, supportedRanges: [BillingRange],
                showsModelBreakdown: Bool, showsTimeSeries: Bool) {
        rangeSelector.update(ranges: supportedRanges, selected: range)
        barsView.isHidden = !showsTimeSeries
        axisRow.isHidden = !showsTimeSeries

        guard let usage else {
            metricsLine.attributedStringValue = Self.metricsLine(totals: nil)
            metricHintButton.isHidden = true
            barsView.update(buckets: [], fillColor: PaneCardStyle.uncachedColor)
            axisRow.update(left: "", right: "")
            legendRow.isHidden = true
            updateModels(groups: [], shows: false)
            return
        }

        let usesUSD = usage.buckets.contains { ($0.metrics.usageUSD ?? 0) > 0 }
        let colors = (usesUSD ? PaneCardStyle.okInk : PaneCardStyle.uncachedInk)
        metricsLine.attributedStringValue = Self.metricsLine(totals: usage.totals)
        metricHintButton.isHidden = usage.totals.usageUSD != nil || Self.hasTokenDetail(usage.totals)
        if showsTimeSeries {
            let buckets = usage.buckets.map { bucket in
                BillingUsageBarsView.Bucket(
                    value: Self.barValue(bucket, usesUSD: usesUSD),
                    caption: Self.bucketCaption(bucket, granularity: usage.granularity, usesUSD: usesUSD))
            }
            barsView.update(buckets: buckets, fillColor: colors)
            axisRow.update(left: Self.axisLeft(usage),
                           right: usage.granularity == .hour ? "现在" : "今天")
            legendRow.isHidden = buckets.isEmpty
            updateLegend(usesUSD: usesUSD, colors: colors)
        } else {
            barsView.update(buckets: [], fillColor: colors)
            legendRow.isHidden = true
        }
        updateModels(groups: usage.groups, shows: showsModelBreakdown)
    }

    /// 图例（与 Token 页同一语法：色块 + 标题 + 数值）
    private func updateLegend(usesUSD: Bool, colors: NSColor) {
        for view in legendRow.arrangedSubviews {
            legendRow.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        let swatch = NSView()
        swatch.translatesAutoresizingMaskIntoConstraints = false
        swatch.wantsLayer = true
        swatch.layer?.backgroundColor = colors.cgColor
        swatch.layer?.cornerRadius = 1.5
        NSLayoutConstraint.activate([
            swatch.widthAnchor.constraint(equalToConstant: 6),
            swatch.heightAnchor.constraint(equalToConstant: 6),
        ])
        legendRow.addArrangedSubview(swatch)
        legendRow.addArrangedSubview(MenuPanelLabel.text(usesUSD ? "花费" : "请求",
                                                         font: PaneCardStyle.legendFont,
                                                         color: PaneCardStyle.tertiaryText))
        legendRow.addArrangedSubview(MenuPanelLabel.spacer())
        legendRow.addArrangedSubview(MenuPanelLabel.text(
            usesUSD ? "按桶金额" : "按桶请求数",
            font: PaneCardStyle.metaFont, color: PaneCardStyle.tertiaryText))
    }

    // MARK: - 模型明细

    private func updateModels(groups: [BillingGroup], shows: Bool) {
        let top = shows
            ? Array(groups.sorted { Self.modelWeight($0.metrics) > Self.modelWeight($1.metrics) }
                .prefix(3))
            : []
        let isHidden = top.isEmpty
        modelsHeader.isHidden = isHidden
        modelStack.isHidden = isHidden
        divider.isHidden = isHidden
        guard !isHidden else {
            clearModelRows()
            modelsSignature = ""
            return
        }

        modelsTrailing.stringValue = "Top " + String(top.count)
        let signature = top.map {
            "\($0.name):\($0.metrics.requestCount):\(Self.modelWeight($0.metrics))"
        }.joined(separator: "|")
        guard signature != modelsSignature else { return }
        modelsSignature = signature
        clearModelRows()
        modelRows = top.map { group in
            let row = BillingModelRow()
            row.update(name: group.name, metrics: group.metrics)
            return row
        }
        for row in modelRows {
            modelStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: modelStack.widthAnchor).isActive = true
        }
    }

    private static func modelWeight(_ metrics: BillingMetrics) -> Double {
        if let usd = metrics.usageUSD { return usd }
        return Double((metrics.inputTokens ?? 0) + (metrics.cachedInputTokens ?? 0)
                      + (metrics.outputTokens ?? 0))
    }

    private func clearModelRows() {
        for row in modelRows {
            modelStack.removeArrangedSubview(row)
            row.removeFromSuperview()
        }
        modelRows = []
    }

#if DEBUG
    /// 快照自证专用（仅 DEBUG）：强制悬停某根柱
    func forceHoverForSnapshot(_ index: Int?) {
        barsView.forceHoverForSnapshot(index)
    }
#endif

    // MARK: - 指标文案

    private static func hasTokenDetail(_ totals: BillingMetrics) -> Bool {
        totals.inputTokens != nil || totals.cachedInputTokens != nil || totals.outputTokens != nil
    }

    /// 指标行：请求 N 次 · 花费 $X · 输入 / 缓存 / 输出
    static func metricsLine(totals: BillingMetrics?) -> NSAttributedString {
        let result = NSMutableAttributedString()
        func append(_ text: String, em: Bool = false, muted: Bool = false) {
            let font = em ? PaneCardStyle.rowValueStrongFont : PaneCardStyle.rowNameFont
            let color = muted ? PaneCardStyle.tertiaryText : PaneCardStyle.secondaryText
            result.append(NSAttributedString(string: text,
                                             attributes: [.font: font, .foregroundColor: color]))
        }
        append("请求 ")
        append(totals.map { "\($0.requestCount)" } ?? "—", em: true)
        append(" 次")
        if let usd = totals?.usageUSD {
            append(" · ", muted: true)
            append("花费 ")
            append(formatUSD(usd), em: true)
        }
        if let totals, hasTokenDetail(totals) {
            append(" · ", muted: true)
            append("输入 \(formatTokenCount(totals.inputTokens ?? 0))")
            append(" · ", muted: true)
            append("缓存 \(formatTokenCount(totals.cachedInputTokens ?? 0))")
            append(" · ", muted: true)
            append("输出 \(formatTokenCount(totals.outputTokens ?? 0))")
        }
        return result
    }

    private static func makeLineLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = PaneCardStyle.rowNameFont
        label.textColor = PaneCardStyle.secondaryText
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }
}
