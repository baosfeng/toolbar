import AppKit
import NetworkMonitorCore

// MARK: - 用量区

/// 用量区 — 表头 + 范围分段、指标两行、柱状图 + 首尾轴、模型 Top3
final class BillingUsageSectionView: NSView {

    /// 切换时间范围
    var onRangeChange: ((BillingRange) -> Void)?

    private let rangeSelector = BillingRangeSegmentedView()
    private let headerRow = NSStackView()
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
        headerRow.addArrangedSubview(usageTitle)
        headerRow.addArrangedSubview(MenuPanelLabel.spacer())
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
    func update(usage: BillingUsage?, range: BillingRange, showsModelBreakdown: Bool) {
        rangeSelector.update(selected: range)

        guard let usage else {
            metricsLine1.attributedStringValue = Self.metricsLine(totals: nil)
            metricsLine2.attributedStringValue = Self.tokenLine(totals: nil)
            barsView.bars = []
            axisRow.update(left: "", right: "")
            updateModels(groups: [], shows: false)
            return
        }

        metricsLine1.attributedStringValue = Self.metricsLine(totals: usage.totals)
        metricsLine2.attributedStringValue = Self.tokenLine(totals: usage.totals)
        barsView.bars = Self.makeBars(usage)
        axisRow.update(left: Self.axisLeft(usage), right: usage.granularity == .hour ? "现在" : "今天")
        updateModels(groups: usage.groups, shows: showsModelBreakdown)
    }

    // MARK: - 模型明细

    /// 重建模型 Top3（按花费降序）；provider 不支持或分组为空时整块隐藏
    private func updateModels(groups: [BillingGroup], shows: Bool) {
        let top = shows
            ? Array(groups.sorted { ($0.metrics.usageUSD ?? 0) > ($1.metrics.usageUSD ?? 0) }.prefix(3))
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
        let signature = top.map { "\($0.name):\($0.metrics.requestCount):\($0.metrics.usageUSD ?? 0)" }
            .joined(separator: "|")
        guard signature != modelsSignature else { return }
        modelsSignature = signature
        clearModelRows()
        modelRows = top.map { group in
            let row = BillingModelRow()
            row.update(name: group.name, requests: group.metrics.requestCount, usd: group.metrics.usageUSD)
            return row
        }
        for row in modelRows {
            modelStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: modelStack.widthAnchor).isActive = true
        }
    }

    private func clearModelRows() {
        for row in modelRows {
            modelStack.removeArrangedSubview(row)
            row.removeFromSuperview()
        }
        modelRows = []
    }

    // MARK: - 柱状图数据

    /// 分桶 → 柱体数据
    ///
    /// `Bar.value` 用微美元整数（避免浮点柱高抖动）；柱数较多时只给最大桶显示数值文案，
    /// 否则 9pt 数值在 25/31 根柱上会互相重叠（原型用悬停提示，这里用稀疏数值代替）。
    private static func makeBars(_ usage: BillingUsage) -> [MenuPanelBarsView.Bar] {
        let buckets = usage.buckets
        let showEveryValue = buckets.count <= 10
        let maxUSD = buckets.map { max(0, $0.metrics.usageUSD ?? 0) }.max() ?? 0
        return buckets.enumerated().map { index, bucket in
            let usd = max(0, bucket.metrics.usageUSD ?? 0)
            let isLast = index == buckets.count - 1
            let showsValue = showEveryValue || (maxUSD > 0 && usd >= maxUSD)
            return MenuPanelBarsView.Bar(label: "",
                                         value: UInt64(min(usd * 1_000_000, 1e15)),
                                         valueText: showsValue ? formatUSD(usd) : "",
                                         isToday: isLast)
        }
    }

    /// 轴左侧标签：首桶时间（M/d 或 HH:00）
    private static func axisLeft(_ usage: BillingUsage) -> String {
        guard let first = usage.buckets.first else { return "" }
        return formatBucketLabel(first.start, granularity: usage.granularity)
    }

    // MARK: - 指标文案

    /// 指标行 1：请求 N 次 · 花费 $X
    private static func metricsLine(totals: BillingMetrics?) -> NSAttributedString {
        let result = NSMutableAttributedString()
        result.append(segment("请求 ", font: BillingPaneStyle.labelFont, color: BillingPaneStyle.secondaryText))
        result.append(segment(totals.map { "\($0.requestCount)" } ?? "—",
                              font: BillingPaneStyle.metricValueFont, color: .labelColor))
        result.append(segment(" 次", font: BillingPaneStyle.labelFont, color: BillingPaneStyle.secondaryText))
        result.append(segment(" · ", font: BillingPaneStyle.labelFont, color: BillingPaneStyle.tertiaryText))
        result.append(segment("花费 ", font: BillingPaneStyle.labelFont, color: BillingPaneStyle.secondaryText))
        result.append(segment(totals?.usageUSD.flatMap { formatUSD($0) } ?? "—",
                              font: BillingPaneStyle.metricValueFont, color: .labelColor))
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

// MARK: - 图表坐标轴 / 分隔线

/// 图表首尾坐标轴 — 左首桶时间、右「现在 / 今天」
final class BillingAxisRow: NSView {

    private let leftLabel = MenuPanelLabel.text("", font: BillingPaneStyle.axisFont,
                                                color: BillingPaneStyle.tertiaryText)
    private let rightLabel = MenuPanelLabel.text("", font: BillingPaneStyle.axisFont,
                                                 color: BillingPaneStyle.tertiaryText)

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        rightLabel.alignment = .right
        let stack = NSStackView(views: [leftLabel, MenuPanelLabel.spacer(), rightLabel])
        stack.orientation = .horizontal
        stack.alignment = .firstBaseline
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 14),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func update(left: String, right: String) {
        leftLabel.stringValue = left
        rightLabel.stringValue = right
    }
}

/// 1pt 浅分隔线（10% 前景色，深浅色自适应）
final class BillingDividerView: NSView {

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 1).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        BillingPaneStyle.hairline.setFill()
        bounds.fill()
    }
}

// MARK: - 模型明细行

/// 模型明细行 — 模型名（等宽截断）+ 请求次数 + 金额（右对齐，最小 52pt）
final class BillingModelRow: MenuPanelRow {

    private let nameLabel: NSTextField
    private let requestLabel: NSTextField
    private let amountLabel: NSTextField

    init() {
        nameLabel = MenuPanelLabel.text("", font: BillingPaneStyle.modelNameFont,
                                        color: BillingPaneStyle.secondaryText)
        requestLabel = MenuPanelLabel.text("", font: BillingPaneStyle.modelRequestFont,
                                           color: BillingPaneStyle.tertiaryText)
        amountLabel = MenuPanelLabel.text("", font: BillingPaneStyle.modelAmountFont, color: .labelColor)
        super.init(height: 22, onClick: nil)
        requestLabel.setContentHuggingPriority(.required, for: .horizontal)
        requestLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        amountLabel.alignment = .right
        amountLabel.setContentHuggingPriority(.required, for: .horizontal)
        amountLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        contentStack.addArrangedSubview(nameLabel)
        contentStack.addArrangedSubview(MenuPanelLabel.spacer())
        contentStack.addArrangedSubview(requestLabel)
        contentStack.addArrangedSubview(amountLabel)
        amountLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 更新一行模型明细
    func update(name: String, requests: Int, usd: Double?) {
        nameLabel.stringValue = name
        nameLabel.toolTip = name
        requestLabel.stringValue = "\(requests) 次"
        amountLabel.stringValue = usd.map { formatUSD($0) } ?? "—"
        setAccessibilityLabel("\(name) \(requests) 次 \(amountLabel.stringValue)")
    }
}
