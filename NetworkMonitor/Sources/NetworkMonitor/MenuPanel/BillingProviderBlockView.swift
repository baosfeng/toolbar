import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - provider 卡（与 Token 分族卡同族）

/// provider 卡 —— 卡头（图标 + 名称 + 状态胶囊 + 时间 + 展开箭头）+ 1–3 额度格 + 迷你走势 + 展开区
///
/// 与 Token 页的卡片同一套语言：`PaneCardBackgroundView` 底（实色面 / 9pt 圆角 / 7×4 内边距）、
/// 卡头 13pt 行、卡内行距 2pt、卡间间距 4pt（由 `BillingPaneView` 的主栈给）。
/// 状态用胶囊文字（正常 / 限流 / 出错 / 查询中），不再用 5pt 圆点。
final class BillingProviderBlockView: NSView {

    // MARK: - 回调

    /// 点卡头：展开 / 收起
    var onToggleExpand: (() -> Void)?
    /// 展开区内切换用量范围
    var onRangeChange: ((BillingRange) -> Void)?
    /// 空态跳转设置（由 BillingPaneView 的 onOpenSettings 统一转出）
    var onOpenSettings: (() -> Void)?
    /// 错误条重试
    var onRetry: (() -> Void)?

    // MARK: - 子视图

    /// 额度格最多列数
    static let maxLimitColumns = BillingLimitLayout.maxColumns

    private let card = PaneCardBackgroundView()
    private let headerRow = MenuPanelRow(height: PaneCardStyle.cardHeadHeight, onClick: nil)
    private let iconView: NSImageView?
    private let nameLabel = MenuPanelLabel.text("", font: PaneCardStyle.cardTitleFont,
                                                color: PaneCardStyle.primaryText)
    private let chip = BillingStatusChipView()
    private let timeLabel = MenuPanelLabel.text("", font: PaneCardStyle.metaFont,
                                                color: PaneCardStyle.tertiaryText)
    private let chevronView: NSImageView?

    /// 额度格（预建 3 个复用）
    var limitCells: [BillingLimitCellView] = []
    private let limitsRow = NSStackView()

    let trendView = BillingMiniTrendView()
    let summaryLabel = MenuPanelLabel.text("", font: PaneCardStyle.metaFont,
                                           color: PaneCardStyle.tertiaryText)
    let summaryRow = NSStackView()

    let usageSection = BillingUsageSectionView()
    private let errorBanner = BillingErrorBannerView()

    /// 数据层契约：快照只含可见 provider（未配置 / 停用的不在里面），
    /// 因此本视图不再有「未配置块」分支，也没有「去设置配置」行内按钮（入口在空态）。
    private var suppressesExpansion = false

    private(set) var providerID: String = ""

    // MARK: - 初始化

    init() {
        iconView = MenuPanelLabel.symbol("creditcard", pointSize: 11, color: PaneCardStyle.accentText)
        chevronView = MenuPanelLabel.symbol("chevron.down", pointSize: 8, color: PaneCardStyle.tertiaryText)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        headerRow.contentStack.spacing = 5
        if let iconView { headerRow.contentStack.addArrangedSubview(iconView) }
        headerRow.contentStack.addArrangedSubview(nameLabel)
        headerRow.contentStack.addArrangedSubview(chip)
        headerRow.contentStack.addArrangedSubview(MenuPanelLabel.spacer())
        headerRow.contentStack.addArrangedSubview(timeLabel)
        if let chevronView { headerRow.contentStack.addArrangedSubview(chevronView) }
        headerRow.onClick = { [weak self] in self?.onToggleExpand?() }

        limitCells = (0..<Self.maxLimitColumns).map { _ in BillingLimitCellView() }
        limitsRow.orientation = .horizontal
        limitsRow.distribution = .fillEqually
        limitsRow.alignment = .top
        limitsRow.spacing = 6
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
        trendView.widthAnchor.constraint(equalToConstant: PaneCardStyle.sparkWidth).isActive = true
        trendView.heightAnchor.constraint(equalToConstant: PaneCardStyle.sparkHeight).isActive = true
        summaryLabel.setContentHuggingPriority(.required, for: .horizontal)
        summaryLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        usageSection.onRangeChange = { [weak self] range in self?.onRangeChange?(range) }
        errorBanner.onRetry = { [weak self] in self?.onRetry?() }

        let body = NSStackView(views: [headerRow, limitsRow, summaryRow,
                                       errorBanner, usageSection])
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = PaneCardStyle.rowSpacing
        body.translatesAutoresizingMaskIntoConstraints = false

        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)
        card.contentView.addSubview(body)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(equalTo: trailingAnchor),
            card.topAnchor.constraint(equalTo: topAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor),
            body.leadingAnchor.constraint(equalTo: card.contentView.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: card.contentView.trailingAnchor),
            body.topAnchor.constraint(equalTo: card.contentView.topAnchor),
            body.bottomAnchor.constraint(equalTo: card.contentView.bottomAnchor),
        ])
        for view in body.arrangedSubviews {
            view.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    // MARK: - 键盘可达

    var focusableRows: [MenuPanelRow] {
        var rows: [MenuPanelRow] = []
        if headerRow.isInteractive { rows.append(headerRow) }
        if !usageSection.isHidden { rows.append(contentsOf: usageSection.focusableRows) }
        if !errorBanner.isHidden { rows.append(errorBanner.retryButtonRow) }
        return rows
    }

    // MARK: - 数据更新

    func update(state: BillingMonitor.ProviderState, isExpanded: Bool) {
        providerID = state.descriptor.id
        let descriptor = state.descriptor
        let supportsUsage = descriptor.supportsUsage
        nameLabel.stringValue = descriptor.displayName
        if let iconView {
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
            iconView.image = NSImage(systemSymbolName: descriptor.symbolName,
                                     accessibilityDescription: nil)?
                .withSymbolConfiguration(config)
            iconView.contentTintColor = PaneCardStyle.accentText
        }

        applyStatus(state)
        // 「—」对用户没有信息量：区分「正在查」/「从未刷新」/「已暂停」
        timeLabel.stringValue = Self.timeText(state)

        limitsRow.isHidden = false
        summaryRow.isHidden = !supportsUsage
        applyLimits(state.balance)
        if supportsUsage { applySummary(state) }

        let expanded = isExpanded && supportsUsage
        usageSection.isHidden = !expanded
        summaryRow.isHidden = expanded || !supportsUsage
        if expanded {
            usageSection.update(usage: state.usage,
                                range: state.range,
                                supportedRanges: descriptor.supportedRanges,
                                showsModelBreakdown: descriptor.supportsModelBreakdown,
                                showsTimeSeries: descriptor.supportsTimeSeries)
        }
        chevronView?.image = NSImage(systemSymbolName: expanded ? "chevron.up" : "chevron.down",
                                     accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 8, weight: .regular))
        chevronView?.isHidden = !supportsUsage

        suppressesExpansion = !supportsUsage
        if suppressesExpansion {
            headerRow.onClick = nil
        } else {
            headerRow.onClick = { [weak self] in self?.onToggleExpand?() }
        }

        let showsError = state.errorMessage != nil
        errorBanner.isHidden = !showsError
        if let message = state.errorMessage, showsError { errorBanner.update(message: message) }

        setAccessibilityLabel("\(descriptor.displayName) 额度")
        invalidateIntrinsicContentSize()
    }

    /// 状态胶囊：出错 > 限流 > 查询中 > 未刷新 > 正常（判据在 NetworkMonitorUI，可单测）
    ///
    /// 「未刷新」这一档是现场反馈的修复点：余额为 nil 的 provider 此前落到 else 显示
    /// 绿色的「正常」，用户看到的却是「正常 + —」，无法判断是哪一环坏了。
    private func applyStatus(_ state: BillingMonitor.ProviderState) {
        let kind = BillingProviderStatusLogic.kind(
            errorMessage: state.errorMessage,
            remainingFractions: (state.balance?.percentLimits ?? []).map(\.remainingFraction),
            isLoading: state.isLoading,
            hasBalance: state.balance.map { !$0.isEmpty } ?? false)
        chip.update(kind: Self.chipKind(kind), text: BillingProviderStatusLogic.text(kind))
    }

    /// 语义档 → 视图档（两者一一对应，集中一处避免散落映射）
    private static func chipKind(_ kind: BillingStatusKind) -> BillingStatusChipView.Kind {
        switch kind {
        case .ok: return .ok
        case .warn: return .warn
        case .error: return .error
        case .loading: return .loading
        case .idle: return .idle
        }
    }

    // MARK: - 文案

    /// 块头「最近刷新」时分：跟随系统 12/24 小时制（见 BillingTimeFormat）
    static func stamp(_ date: Date) -> String { BillingTimeFormat.string(date) }

    /// 块头右侧时间文案：成功过给时分，否则说明「为什么还没有时间」
    static func timeText(_ state: BillingMonitor.ProviderState) -> String {
        if let updated = state.lastUpdated { return stamp(updated) }
        if state.isLoading { return "查询中" }
        return "未刷新"
    }
}
