import AppKit
import NetworkMonitorCore

// MARK: - provider 聚合块

/// provider 聚合块 — 标题行 + 1–3 列额度 + 迷你趋势/摘要 + 可展开用量区
///
/// 收起态只占约 100pt：标题行、额度格（并排）、一行趋势与摘要；
/// 点标题行就地展开该 provider 的完整柱状图与模型明细（同一时刻只允许一个展开）。
/// 只查额度、没有用量接口的 provider（`supportsUsage == false`）整块更紧凑：
/// 不显示摘要行、不显示展开箭头、标题行不响应点击。
final class BillingProviderBlockView: NSView {

    // MARK: - 回调

    /// 点标题行：展开 / 收起
    var onToggleExpand: (() -> Void)?
    /// 展开区内切换用量范围
    var onRangeChange: ((BillingRange) -> Void)?
    /// 未配置态跳转到设置页配置凭据
    var onOpenSettings: (() -> Void)?
    /// 错误条重试
    var onRetry: (() -> Void)?

    // MARK: - 子视图

    /// 额度格最多列数（5 小时 / 每周 / 每月）
    static let maxLimitColumns = BillingLimitLayout.maxColumns

    private let card = MenuPanelCardView()
    private let headerRow = MenuPanelRow(height: 16, onClick: nil)
    private let iconView: NSImageView?
    private let nameLabel = MenuPanelLabel.text("", font: BillingPaneStyle.blockNameFont,
                                                color: .labelColor)
    private let dotView = BillingStatusDotView()
    private let timeLabel = MenuPanelLabel.text("", font: BillingPaneStyle.stampFont,
                                                color: BillingPaneStyle.tertiaryText)
    private let chevronView: NSImageView?

    /// 额度格（预建 3 个复用，按 provider 实际窗口数显示前 N 个）
    var limitCells: [BillingLimitCellView] = []
    private let limitsRow = NSStackView()

    let trendView = BillingMiniTrendView()
    let summaryLabel = MenuPanelLabel.text("", font: BillingPaneStyle.cellTitleFont,
                                           color: BillingPaneStyle.tertiaryText)
    let summaryRow = NSStackView()

    let usageSection = BillingUsageSectionView()
    private let errorBanner = BillingErrorBannerView()

    /// 未配置态的紧凑行（一行文案 +「去设置配置」按钮）
    private let promptLabel = MenuPanelLabel.text("", font: BillingPaneStyle.cellTitleFont,
                                                  color: BillingPaneStyle.tertiaryText)
    private let settingsButtonRow = BillingPrimaryButtonRow(title: "去设置配置")
    private let setupRow = NSStackView()
    /// 该 provider 没有可展开的用量内容（只查额度的 provider）
    private var suppressesExpansion = false

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

        limitCells = (0..<Self.maxLimitColumns).map { _ in BillingLimitCellView() }
        limitsRow.orientation = .horizontal
        limitsRow.distribution = .fillEqually
        // 三列窄格可能出现「角标独占一行」，顶部对齐避免百分比基线随角标有无而漂移
        limitsRow.alignment = .top
        limitsRow.spacing = 10
        for (index, cell) in limitCells.enumerated() {
            limitsRow.addArrangedSubview(cell)
            cell.isHidden = index > 0
        }

        summaryRow.orientation = .horizontal
        summaryRow.alignment = .bottom
        summaryRow.spacing = 6
        summaryRow.addArrangedSubview(trendView)
        summaryRow.addArrangedSubview(summaryLabel)
        trendView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        summaryLabel.setContentHuggingPriority(.required, for: .horizontal)
        summaryLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        usageSection.onRangeChange = { [weak self] range in self?.onRangeChange?(range) }
        errorBanner.onRetry = { [weak self] in self?.onRetry?() }

        settingsButtonRow.setAccessibilityLabel("去设置配置额度 Provider")
        settingsButtonRow.onClick = { [weak self] in self?.onOpenSettings?() }
        setupRow.orientation = .horizontal
        setupRow.alignment = .centerY
        setupRow.spacing = 8
        setupRow.addArrangedSubview(promptLabel)
        setupRow.addArrangedSubview(MenuPanelLabel.spacer())
        setupRow.addArrangedSubview(settingsButtonRow)

        let body = NSStackView(views: [headerRow, limitsRow, summaryRow, setupRow,
                                       errorBanner, usageSection])
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
        var rows: [MenuPanelRow] = []
        // 只查额度的 provider 标题行不可点，不进入焦点遍历（未配置态仍需点开凭据表单）
        if headerRow.isInteractive { rows.append(headerRow) }
        if !setupRow.isHidden { rows.append(settingsButtonRow) }
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
        let supportsUsage = descriptor.supportsUsage
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
        summaryRow.isHidden = !state.isConfigured || !supportsUsage
        // 未配置块只占一行：文案 +「去设置配置」（凭据输入统一收进设置窗口）
        setupRow.isHidden = state.isConfigured

        if state.isConfigured {
            applyLimits(state.balance)
            if supportsUsage { applySummary(state) }
        } else {
            promptLabel.stringValue = "未配置凭据，无法查询额度"
        }

        // 能力位压住传入的展开态：没有用量接口就没有可展开内容
        let expanded = isExpanded && state.isConfigured && supportsUsage
        usageSection.isHidden = !expanded
        // 展开后用完整柱状图承载趋势，收起态的迷你趋势与摘要行随之隐藏，避免同一指标画两遍
        summaryRow.isHidden = !state.isConfigured || expanded || !supportsUsage
        if expanded {
            usageSection.update(usage: state.usage,
                                range: state.range,
                                showsModelBreakdown: descriptor.supportsModelBreakdown,
                                showsTimeSeries: descriptor.supportsTimeSeries)
        }
        chevronView?.image = NSImage(systemSymbolName: expanded ? "chevron.up" : "chevron.down",
                                     accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 8, weight: .regular))
        chevronView?.isHidden = !state.isConfigured || !supportsUsage

        // 只查额度 / 未配置的 provider 标题行不响应点击（配置入口在「去设置配置」）
        suppressesExpansion = !state.isConfigured || !supportsUsage
        if suppressesExpansion {
            headerRow.onClick = nil
        } else {
            headerRow.onClick = { [weak self] in self?.onToggleExpand?() }
        }

        let showsError = state.isConfigured && state.errorMessage != nil
        errorBanner.isHidden = !showsError
        if let message = state.errorMessage, showsError { errorBanner.update(message: message) }

        setAccessibilityLabel("\(descriptor.displayName) 额度")
        invalidateIntrinsicContentSize()
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