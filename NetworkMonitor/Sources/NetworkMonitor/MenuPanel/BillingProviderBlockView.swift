import AppKit
import NetworkMonitorCore

// MARK: - provider 聚合块

/// provider 聚合块 — 标题行 + 双列额度 + 迷你趋势/摘要 + 可展开用量区
///
/// 收起态只占约 100pt：标题行、两条额度（并排）、一行趋势与摘要；
/// 点标题行就地展开该 provider 的完整柱状图与模型明细（同一时刻只允许一个展开）。
final class BillingProviderBlockView: NSView {

    // MARK: - 回调

    /// 点标题行：展开 / 收起
    var onToggleExpand: (() -> Void)?
    /// 展开区内切换用量范围
    var onRangeChange: ((BillingRange) -> Void)?
    /// 未配置态提交凭据
    var onSaveCredential: ((String) -> Void)?
    /// 未配置态跳转 provider 站点
    var onOpenSite: (() -> Void)?
    /// 错误条重试
    var onRetry: (() -> Void)?

    // MARK: - 子视图

    private let card = MenuPanelCardView()
    private let headerRow = MenuPanelRow(height: 16, onClick: nil)
    private let iconView: NSImageView?
    private let nameLabel = MenuPanelLabel.text("", font: BillingPaneStyle.blockNameFont,
                                                color: .labelColor)
    private let dotView = BillingStatusDotView()
    private let timeLabel = MenuPanelLabel.text("", font: BillingPaneStyle.stampFont,
                                                color: BillingPaneStyle.tertiaryText)
    private let chevronView: NSImageView?

    private let leftCell = BillingLimitCellView()
    private let rightCell = BillingLimitCellView()
    private let limitsRow = NSStackView()

    private let trendView = BillingMiniTrendView()
    private let summaryLabel = MenuPanelLabel.text("", font: BillingPaneStyle.cellTitleFont,
                                                   color: BillingPaneStyle.tertiaryText)
    private let summaryRow = NSStackView()

    let usageSection = BillingUsageSectionView()
    let setupView = BillingCredentialSetupView()
    private let errorBanner = BillingErrorBannerView()

    /// 未配置态的紧凑行（一行文案 + 配置按钮），点开后才展开完整表单
    private let promptLabel = MenuPanelLabel.text("", font: BillingPaneStyle.cellTitleFont,
                                                  color: BillingPaneStyle.tertiaryText)
    private let setupButtonRow = BillingPrimaryButtonRow(title: "配置")
    private let setupRow = NSStackView()
    /// 未配置块是否已展开完整凭据表单
    private var isSetupExpanded = false

    /// 当前 provider id（回调时带上，避免控制器再维护一份映射）
    private(set) var providerID: String = ""

    // MARK: - 初始化

    init() {
        iconView = MenuPanelLabel.symbol("creditcard", pointSize: 12,
                                         color: MenuPanelStyle.accentColor)
        chevronView = MenuPanelLabel.symbol("chevron.down", pointSize: 8,
                                            color: BillingPaneStyle.tertiaryText)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        headerRow.contentStack.spacing = 5
        if let iconView { headerRow.contentStack.addArrangedSubview(iconView) }
        headerRow.contentStack.addArrangedSubview(nameLabel)
        headerRow.contentStack.addArrangedSubview(MenuPanelLabel.spacer())
        headerRow.contentStack.addArrangedSubview(dotView)
        headerRow.contentStack.addArrangedSubview(timeLabel)
        if let chevronView { headerRow.contentStack.addArrangedSubview(chevronView) }
        headerRow.onClick = { [weak self] in self?.onToggleExpand?() }

        limitsRow.orientation = .horizontal
        limitsRow.distribution = .fillEqually
        limitsRow.spacing = 10
        limitsRow.addArrangedSubview(leftCell)
        limitsRow.addArrangedSubview(rightCell)

        summaryRow.orientation = .horizontal
        summaryRow.alignment = .bottom
        summaryRow.spacing = 6
        summaryRow.addArrangedSubview(trendView)
        summaryRow.addArrangedSubview(summaryLabel)
        trendView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        summaryLabel.setContentHuggingPriority(.required, for: .horizontal)
        summaryLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        usageSection.onRangeChange = { [weak self] range in self?.onRangeChange?(range) }
        setupView.onSave = { [weak self] key in self?.onSaveCredential?(key) }
        setupView.onOpenSite = { [weak self] in self?.onOpenSite?() }
        errorBanner.onRetry = { [weak self] in self?.onRetry?() }

        setupButtonRow.setAccessibilityLabel("配置凭据")
        setupButtonRow.onClick = { [weak self] in self?.toggleSetup() }
        setupRow.orientation = .horizontal
        setupRow.alignment = .centerY
        setupRow.spacing = 8
        setupRow.addArrangedSubview(promptLabel)
        setupRow.addArrangedSubview(MenuPanelLabel.spacer())
        setupRow.addArrangedSubview(setupButtonRow)

        let body = NSStackView(views: [headerRow, limitsRow, summaryRow, setupRow,
                                       errorBanner, usageSection, setupView])
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 6
        body.translatesAutoresizingMaskIntoConstraints = false

        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)
        card.addSubview(body)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(equalTo: trailingAnchor),
            card.topAnchor.constraint(equalTo: topAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor),
            body.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 9),
            body.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -9),
            body.topAnchor.constraint(equalTo: card.topAnchor, constant: 7),
            body.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8),
        ])
        for view in body.arrangedSubviews {
            view.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    // MARK: - 键盘可达

    /// 键盘可达行：标题行 → 配置入口 / 配置输入 → 展开区范围按钮 → 重试
    var focusableRows: [MenuPanelRow] {
        var rows: [MenuPanelRow] = [headerRow]
        if !setupRow.isHidden { rows.append(setupButtonRow) }
        if !setupView.isHidden { rows.append(contentsOf: setupView.focusableRows) }
        if !usageSection.isHidden { rows.append(contentsOf: usageSection.focusableRows) }
        if !errorBanner.isHidden { rows.append(errorBanner.retryButtonRow) }
        return rows
    }

    // MARK: - 数据更新

    /// 应用单个 provider 的状态
    ///
    /// - Parameters:
    ///   - state: provider 状态快照
    ///   - isExpanded: 是否处于展开态（展开态额外渲染用量区）
    func update(state: BillingMonitor.ProviderState, isExpanded: Bool) {
        providerID = state.descriptor.id
        let descriptor = state.descriptor
        nameLabel.stringValue = descriptor.displayName
        if let iconView {
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
            iconView.image = NSImage(systemSymbolName: descriptor.symbolName,
                                     accessibilityDescription: nil)?
                .withSymbolConfiguration(config)
            iconView.contentTintColor = MenuPanelStyle.accentColor
        }

        dotView.kind = !state.isConfigured ? .idle : (state.errorMessage == nil ? .ok : .warn)
        if state.isConfigured {
            timeLabel.stringValue = state.lastUpdated.map(Self.stamp) ?? (state.isLoading ? "查询中" : "—")
        } else {
            timeLabel.stringValue = "未配置"
        }

        limitsRow.isHidden = !state.isConfigured
        summaryRow.isHidden = !state.isConfigured
        if state.isConfigured { isSetupExpanded = false }
        // 未配置块默认只占一行；点「配置」或标题行才展开完整表单
        setupRow.isHidden = state.isConfigured || isSetupExpanded
        setupView.isHidden = state.isConfigured || !isSetupExpanded

        if state.isConfigured {
            applyLimits(state.balance)
            applySummary(state)
        } else {
            promptLabel.stringValue = Self.prompt(for: descriptor)
            setupView.update(placeholder: descriptor.credentialHint,
                             linkText: Self.linkText(for: descriptor),
                             showsLink: descriptor.credentialPageURL != nil)
        }

        let expanded = isExpanded && state.isConfigured
        usageSection.isHidden = !expanded
        // 展开后用完整柱状图承载趋势，收起态的迷你趋势与摘要行随之隐藏，避免同一指标画两遍
        summaryRow.isHidden = !state.isConfigured || expanded
        if expanded {
            usageSection.update(usage: state.usage,
                                range: state.range,
                                showsModelBreakdown: descriptor.supportsModelBreakdown,
                                showsTimeSeries: descriptor.supportsTimeSeries)
        }
        chevronView?.image = NSImage(systemSymbolName: expanded ? "chevron.up" : "chevron.down",
                                     accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 8, weight: .regular))
        chevronView?.isHidden = !state.isConfigured

        let showsError = state.isConfigured && state.errorMessage != nil
        errorBanner.isHidden = !showsError
        if let message = state.errorMessage, showsError { errorBanner.update(message: message) }

        setAccessibilityLabel("\(descriptor.displayName) 额度")
        invalidateIntrinsicContentSize()
    }

    // MARK: - 额度格

    /// 最多展示两条百分比限额（会话 / 每周）；只有金额型余额时左格显示可用金额
    private func applyLimits(_ balance: BillingBalance?) {
        let limits = balance?.percentLimits ?? []
        if let first = limits.first {
            leftCell.update(limit: first)
            leftCell.isHidden = false
        } else if let total = balance?.totalAvailableUSD {
            leftCell.update(amount: formatUSD(total), title: "可用")
            leftCell.isHidden = false
        } else {
            leftCell.clear()
            leftCell.isHidden = false
        }
        if limits.count > 1 {
            rightCell.update(limit: limits[1])
            rightCell.isHidden = false
        } else {
            rightCell.isHidden = true
        }
    }

    // MARK: - 摘要与趋势

    /// 摘要行：有分桶能力时画迷你趋势，右侧给请求数与 token 汇总
    private func applySummary(_ state: BillingMonitor.ProviderState) {
        let descriptor = state.descriptor
        let usage = state.usage
        let values: [Double]
        if descriptor.supportsTimeSeries, let usage {
            values = usage.buckets.map { Double($0.metrics.requestCount) }
        } else {
            values = []
        }
        if values.count >= 2 {
            trendView.update(values: values)
            trendView.isHidden = false
        } else {
            trendView.isHidden = true
        }

        var parts: [String] = []
        if let totals = usage?.totals {
            parts.append("\(totals.requestCount) 次")
            if let input = totals.inputTokens {
                parts.append("入 \(formatTokenCount(input))")
            }
        } else {
            parts.append(state.isLoading ? "查询中…" : "暂无用量")
        }
        summaryLabel.stringValue = parts.joined(separator: " · ")
    }

    // MARK: - 文案

    /// 页头时间戳（HH:mm）
    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static func stamp(_ date: Date) -> String { stampFormatter.string(from: date) }

    /// 未配置态的提示文案
    private static func prompt(for descriptor: BillingMonitor.ProviderDescriptor) -> String {
        "粘贴 \(descriptor.credentialHint) 开始监控"
    }

    /// 展开 / 收起未配置块的凭据表单
    func toggleSetup() {
        isSetupExpanded.toggle()
        setupRow.isHidden = isSetupExpanded
        setupView.isHidden = !isSetupExpanded
    }

    /// 配置态链接文案（Ollama 点明域名，其余用通用文案）
    static func linkText(for descriptor: BillingMonitor.ProviderDescriptor) -> String {
        if descriptor.displayName == "Ollama", let host = descriptor.credentialPageURL?.host {
            return "在 \(host) 获取 API Key"
        }
        return "前往 \(descriptor.displayName) 网站获取凭据"
    }
}

// MARK: - 状态圆点

/// provider 状态圆点 — 正常绿 / 异常橙 / 未配置灰
final class BillingStatusDotView: NSView {

    enum Kind {
        case ok
        case warn
        case idle
    }

    var kind: Kind = .idle { didSet { needsDisplay = true } }

    override var intrinsicContentSize: NSSize { NSSize(width: 5, height: 5) }

    override func draw(_ dirtyRect: NSRect) {
        let color: NSColor
        switch kind {
        case .ok:   color = .systemGreen
        case .warn: color = .systemOrange
        case .idle: color = .tertiaryLabelColor
        }
        color.setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 0, dy: 0)).fill()
    }
}