import AppKit
import NetworkMonitorCore

// MARK: - 用量区

/// 用量区 — 表头 + 范围分段、指标两行、柱状图 + 首尾轴、模型 Top3
final class BillingUsageSectionView: NSView {

    /// 切换时间范围
    var onRangeChange: ((BillingRange) -> Void)?

    private let rangeSelector = BillingRangeSegmentedView()
    private let headerRow = NSStackView()
    /// 明细缺失说明入口（悬停提示；正常数据下隐藏）
    private let metricHintButton = NSButton()
    private let metricsLine1 = BillingUsageSectionView.makeLineLabel()
    private let metricsLine2 = BillingUsageSectionView.makeLineLabel()
    private let barsView = MenuPanelBarsView()
    private let axisRow = BillingAxisRow()
    private let divider = BillingDividerView()
    // 按模型表头自建（MenuPanelHeaderRow 内部标题色固化，强制外观下会错色）
    private let modelsHeader = NSStackView()
    private let modelsTitle = MenuPanelLabel.text("按模型", font: BillingPaneStyle.cardTitleFont,
                                                 color: BillingPaneStyle.secondaryText)
    private let modelsTrailing = MenuPanelLabel.text("", font: BillingPaneStyle.axisFont,
                                                     color: BillingPaneStyle.tertiaryText)
    private let modelStack = NSStackView()
    private var modelRows: [BillingModelRow] = []
    /// 模型行签名 — 内容未变化时跳过重建
    private var modelsSignature = ""

    // MARK: - 初始化

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        rangeSelector.onSelect = { [weak self] range in self?.onRangeChange?(range) }

        let usageTitle = MenuPanelLabel.text("用量", font: BillingPaneStyle.cardTitleFont,
                                             color: BillingPaneStyle.secondaryText)
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 6
        // 服务端不返回金额 / token 时的说明入口（悬停提示），正常数据下隐藏
        metricHintButton.image = NSImage(systemSymbolName: "questionmark.circle",
                                         accessibilityDescription: "用量明细说明")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .regular))
        metricHintButton.isBordered = false
        metricHintButton.bezelStyle = .inline
        metricHintButton.contentTintColor = BillingPaneStyle.secondaryText
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

        // 柱状图无障碍标签按额度页语义覆盖（复用视图默认是「近 6 日下行流量」）
        barsView.setAccessibilityLabel("用量柱状图")
        // 额度页桶数多（24h=25、30d=31），8pt 间距会把柱宽压到 3pt 以下，调小到 3pt
        barsView.columnGap = 3

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
        modelStack.spacing = 1
        modelStack.isHidden = true
        modelsHeader.isHidden = true
        divider.isHidden = true

        let stack = NSStackView(views: [headerRow, metricsLine1, metricsLine2, barsView, axisRow,
                                        divider, modelsHeader, modelStack])
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

    /// 键盘可达行：三个范围按钮
    var focusableRows: [MenuPanelRow] { rangeSelector.focusableRows }

    // MARK: - 数据更新

    /// 更新用量区
    ///
    /// - Parameters:
    ///   - usage: 用量数据（nil = 尚无成功数据）
    ///   - range: 当前范围（同步分段选中态）
    ///   - showsModelBreakdown: provider 是否提供按模型明细
    ///   - showsTimeSeries: provider 是否支持时间序列；false 时整块隐藏柱状图与时间轴
    ///     （服务端不提供分桶的 provider 不用「明细首 100 条」拼一张严重低估的图）
    func update(usage: BillingUsage?, range: BillingRange, showsModelBreakdown: Bool,
                showsTimeSeries: Bool) {
        rangeSelector.update(selected: range)
        // 时间轴/柱状图显隐与数据无关，先按 provider 能力定，后面只填数据
        barsView.isHidden = !showsTimeSeries
        axisRow.isHidden = !showsTimeSeries

        guard let usage else {
            metricsLine1.attributedStringValue = Self.metricsLine(totals: nil)
            metricsLine2.attributedStringValue = Self.tokenLine(totals: nil)
            metricsLine2.isHidden = false
            metricHintButton.isHidden = true
            barsView.bars = []
            axisRow.update(left: "", right: "")
            updateModels(groups: [], shows: false)
            return
        }

        metricsLine1.attributedStringValue = Self.metricsLine(totals: usage.totals)
        let hasTokens = Self.hasTokenDetail(usage.totals)
        metricsLine2.isHidden = !hasTokens
        if hasTokens {
            metricsLine2.attributedStringValue = Self.tokenLine(totals: usage.totals)
        }
        // 金额与 token 都缺（遗留计划只返回 request_count）：正文不占位，改由「?」悬停说明
        metricHintButton.isHidden = usage.totals.usageUSD != nil || hasTokens
        if showsTimeSeries {
            barsView.bars = Self.makeBars(usage)
            axisRow.update(left: Self.axisLeft(usage),
                           right: usage.granularity == .hour ? "现在" : "今天")
        } else {
            barsView.bars = []
        }
        updateModels(groups: usage.groups, shows: showsModelBreakdown)
    }

    // MARK: - 模型明细

    /// 重建模型 Top3；provider 不支持或分组为空时整块隐藏
    ///
    /// 排序键：有金额按金额降序（Ollama），无金额按 token 合计降序（编码计划类 provider）。
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

        modelsTrailing.stringValue = "Top \(top.count)"
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

    /// 模型排序权重：金额优先，无金额时用 token 合计（输入 + 缓存 + 输出）
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

    // MARK: - 柱状图数据

    /// 分桶 → 柱体数据
    ///
    /// 度量自适应：优先按金额绘制；遗留计划只返回请求数（无 usage_usd）时改用请求数，
    /// 否则所有柱高为 0、数值全是 "$0.000"，图表不可读。
    /// 柱数较多时只给最大桶显示数值文案，避免 9pt 数值互相重叠。
    private static func makeBars(_ usage: BillingUsage) -> [MenuPanelBarsView.Bar] {
        let buckets = usage.buckets
        let showEveryValue = buckets.count <= 6
        let usesUSD = buckets.contains { ($0.metrics.usageUSD ?? 0) > 0 }
        let values = buckets.map { bucket -> Double in
            usesUSD ? max(0, bucket.metrics.usageUSD ?? 0) : Double(max(0, bucket.metrics.requestCount))
        }
        let maxValue = values.max() ?? 0
        return buckets.enumerated().map { index, bucket in
            let value = values[index]
            let isLast = index == buckets.count - 1
            let showsValue = maxValue > 0 && (showEveryValue || value >= maxValue)
            let valueText: String
            if !showsValue {
                valueText = ""
            } else if usesUSD {
                valueText = formatUSD(value)
            } else {
                valueText = "\(Int(value)) 次"
            }
            let rawValue: UInt64 = usesUSD
                ? UInt64(min(value * 1_000_000, 1e15))
                : UInt64(min(value, 1e15))
            // 悬停提示：桶的时间范围 + 完整数值（不显示时也能看到这一小时/一天的数据）
            let startLabel = formatBucketLabel(bucket.start, granularity: usage.granularity)
            let endLabel = formatBucketLabel(bucket.end, granularity: usage.granularity)
            let detail = usesUSD
                ? "\(startLabel)–\(endLabel) · \(formatUSD(value))"
                : "\(startLabel)–\(endLabel) · \(Int(value)) 次"
            return MenuPanelBarsView.Bar(label: "",
                                         value: rawValue,
                                         valueText: valueText,
                                         isToday: isLast,
                                         detail: detail)
        }
    }

    /// 轴左侧标签：首桶时间（M/d 或 HH:00）
    private static func axisLeft(_ usage: BillingUsage) -> String {
        guard let first = usage.buckets.first else { return "" }
        return formatBucketLabel(first.start, granularity: usage.granularity)
    }

    // MARK: - 指标文案

    /// 是否有 token 明细（遗留计划不返回；全空时整行隐藏）
    private static func hasTokenDetail(_ totals: BillingMetrics) -> Bool {
        totals.inputTokens != nil || totals.cachedInputTokens != nil || totals.outputTokens != nil
    }

    /// 指标行 1：请求 N 次 · 花费 $X
    private static func metricsLine(totals: BillingMetrics?) -> NSAttributedString {
        let result = NSMutableAttributedString()
        result.append(segment("请求 ", font: BillingPaneStyle.labelFont, color: BillingPaneStyle.secondaryText))
        result.append(segment(totals.map { "\($0.requestCount)" } ?? "—",
                              font: BillingPaneStyle.metricValueFont, color: .labelColor))
        result.append(segment(" 次", font: BillingPaneStyle.labelFont, color: BillingPaneStyle.secondaryText))
        // 金额缺失（遗留计划）时不占位，说明见表头「?」
        if let usd = totals?.usageUSD {
            result.append(segment(" · ", font: BillingPaneStyle.labelFont,
                                  color: BillingPaneStyle.tertiaryText))
            result.append(segment("花费 ", font: BillingPaneStyle.labelFont,
                                  color: BillingPaneStyle.secondaryText))
            result.append(segment(formatUSD(usd), font: BillingPaneStyle.metricValueFont,
                                  color: .labelColor))
        }
        return result
    }

    /// 指标行 2：输入 / 缓存 / 输出 token
    private static func tokenLine(totals: BillingMetrics?) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let items: [(String, String)] = [
            ("输入 ", tokenText(totals?.inputTokens ?? nil)),
            ("缓存 ", tokenText(totals?.cachedInputTokens ?? nil)),
            ("输出 ", tokenText(totals?.outputTokens ?? nil)),
        ]
        for (index, item) in items.enumerated() {
            if index > 0 {
                result.append(segment(" · ", font: BillingPaneStyle.labelFont,
                                      color: BillingPaneStyle.tertiaryText))
            }
            result.append(segment(item.0, font: BillingPaneStyle.labelFont,
                                  color: BillingPaneStyle.secondaryText))
            result.append(segment(item.1, font: BillingPaneStyle.monoFont,
                                  color: BillingPaneStyle.secondaryText))
        }
        return result
    }

    private static func tokenText(_ value: Int?) -> String {
        value.map { formatTokenCount($0) } ?? "—"
    }

    private static func segment(_ text: String, font: NSFont, color: NSColor) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
    }

    private static func makeLineLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = BillingPaneStyle.labelFont
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }
}
