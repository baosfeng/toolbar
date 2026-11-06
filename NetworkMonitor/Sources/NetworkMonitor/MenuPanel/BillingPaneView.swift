import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 额度页（聚合视图 · 与 Token 页同族）

/// 额度页 —— 一次展示全部可见 provider 的额度卡，点卡头就地展开用量明细
///
/// 版式与 Token 页同一套语言：页头一行（主体名 + 弹簧 + 时间 + 刷新）→ Hero（最低剩余）
/// → provider 卡片栈（间距 4pt）→ 页脚状态带。0 个可见 provider 时渲染空态 +「去设置配置」。
/// 未配置 provider 的过滤是**数据层契约**（`BillingVisibilityRule` + BillingMonitor 快照），
/// 本视图只消费结果，不再自行过滤。
final class BillingPaneView: MenuPanelPaneView {

    // MARK: - 回调

    var onRefresh: (() -> Void)?
    var onRetry: (() -> Void)?
    var onRangeChange: ((BillingRange, String) -> Void)?
    var onOpenSettings: (() -> Void)?
    var onContentChanged: (() -> Void)?

    // MARK: - 子视图

    private let headerRow = NSView()
    private let titleLabel = MenuPanelLabel.text("额度", font: PaneCardStyle.cardTitleFont,
                                                 color: PaneCardStyle.secondaryText)
    private let timeLabel = MenuPanelLabel.text("—", font: PaneCardStyle.metaFont,
                                                color: PaneCardStyle.tertiaryText)
    private let refreshRow = BillingIconButtonRow(symbolName: "arrow.clockwise")
    private let heroView = BillingHeroView()
    private let blockStack = NSStackView()
    private let stateBand = PaneStateBandView()
    private let emptyView = BillingEmptyView()

    private var blocks: [String: BillingProviderBlockView] = [:]
    private var blockOrder: [String] = []
    private var expandedProviderID: String?
    private var snapshot: BillingMonitor.Snapshot?

    // MARK: - 初始化

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        timeLabel.alignment = .right
        refreshRow.onClick = { [weak self] in self?.onRefresh?() }
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)

        let headerStack = NSStackView(views: [titleLabel, MenuPanelLabel.spacer(), timeLabel, refreshRow])
        headerStack.orientation = .horizontal
        headerStack.alignment = .centerY
        headerStack.spacing = 6
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        headerRow.addSubview(headerStack)
        NSLayoutConstraint.activate([
            headerStack.leadingAnchor.constraint(equalTo: headerRow.leadingAnchor),
            headerStack.trailingAnchor.constraint(equalTo: headerRow.trailingAnchor),
            headerStack.topAnchor.constraint(equalTo: headerRow.topAnchor),
            headerStack.bottomAnchor.constraint(equalTo: headerRow.bottomAnchor),
            headerRow.heightAnchor.constraint(equalToConstant: PaneCardStyle.pageHeadHeight),
        ])

        blockStack.orientation = .vertical
        blockStack.alignment = .leading
        blockStack.spacing = PaneCardStyle.cardSpacing

        emptyView.isHidden = true
        emptyView.onConfigure = { [weak self] in self?.onOpenSettings?() }

        let root = NSStackView(views: [headerRow, heroView, blockStack, emptyView,
                                       MenuPanelLabel.spacer(), stateBand])
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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

#if DEBUG
    /// 快照自证专用（仅 DEBUG）：强制展开指定 provider 的用量区
    func expandForPreview(_ providerID: String?) {
        expandedProviderID = providerID
        guard let snapshot else { return }
        for state in snapshot.states {
            blocks[state.descriptor.id]?.update(state: state,
                                                isExpanded: expandedProviderID == state.descriptor.id)
        }
        onContentChanged?()
    }

    /// 快照自证专用（仅 DEBUG）：强制悬停某根柱
    func forceChartHoverForSnapshot(_ index: Int?) {
        guard let snapshot else { return }
        for state in snapshot.states where expandedProviderID == state.descriptor.id {
            blocks[state.descriptor.id]?.usageSection.forceHoverForSnapshot(index)
        }
    }
#endif

    // MARK: - 键盘可达

    override var focusableRows: [MenuPanelRow] {
        guard let snapshot, !snapshot.states.isEmpty else {
            return emptyView.focusableRows
        }
        var rows: [MenuPanelRow] = [refreshRow]
        for state in snapshot.states {
            if let block = blocks[state.descriptor.id] {
                rows.append(contentsOf: block.focusableRows)
            }
        }
        return rows
    }

    // MARK: - 数据更新

    func update(_ snapshot: BillingMonitor.Snapshot) {
        self.snapshot = snapshot
        let hasProvider = !snapshot.states.isEmpty
        emptyView.isHidden = hasProvider
        headerRow.isHidden = !hasProvider
        heroView.isHidden = !hasProvider
        blockStack.isHidden = !hasProvider
        stateBand.isHidden = !hasProvider
        if let expanded = expandedProviderID,
           !snapshot.states.contains(where: { $0.descriptor.id == expanded }) {
            expandedProviderID = nil
        }
        guard hasProvider else {
            clearBlocks()
            // 空态文案随原因分支（注册表全空 / 全部未配置 / 全部停用）。
            // `emptyReason` 由数据层给；本分支尚未合入该字段，先走 .unknown，
            // 合并行为分支后把这一行换成 `emptyView.update(reason: snapshot.emptyReason)`。
            emptyView.update(reason: .unknown)
            return
        }
        syncBlocks(snapshot.states)
        let stamp = Self.latestStamp(snapshot.states)
        timeLabel.stringValue = stamp
        heroView.update(hero: Self.hero(from: snapshot.states), clock: "实时 " + stamp)
        stateBand.update(items: [
            (key: "Provider", value: "\(snapshot.states.count)"),
            (key: "最近刷新", value: stamp),
            // 单位档由 Core 侧设置提供；该 API 尚未合入本分支，先给 nil（状态带自动跳过），
            // 合并行为分支后在这里接上（视图不改排版，只换取值来源）。
            (key: "单位", value: Self.unitLabel),
        ])
        for state in snapshot.states {
            blocks[state.descriptor.id]?.update(state: state,
                                                isExpanded: expandedProviderID == state.descriptor.id)
        }
    }

    /// 按 provider 顺序重建卡视图（仅在可见集合变化时）
    private func syncBlocks(_ states: [BillingMonitor.ProviderState]) {
        let ids = states.map { $0.descriptor.id }
        guard blockOrder != ids else { return }
        clearBlocks()
        for state in states {
            let id = state.descriptor.id
            let block = BillingProviderBlockView()
            block.onToggleExpand = { [weak self] in self?.toggleExpand(id) }
            block.onRangeChange = { [weak self] range in self?.onRangeChange?(range, id) }
            block.onOpenSettings = { [weak self] in self?.onOpenSettings?() }
            block.onRetry = { [weak self] in self?.onRetry?() }
            blockStack.addArrangedSubview(block)
            block.widthAnchor.constraint(equalTo: blockStack.widthAnchor).isActive = true
            blocks[id] = block
        }
        blockOrder = ids
    }

    private func clearBlocks() {
        for view in blockStack.arrangedSubviews {
            blockStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        blocks.removeAll()
        blockOrder = []
    }

    /// 展开 / 收起（同一时刻只允许一个展开）
    private func toggleExpand(_ providerID: String) {
        guard let snapshot, let state = snapshot.state(for: providerID) else { return }
        guard state.isConfigured else { return }
        expandedProviderID = (expandedProviderID == providerID) ? nil : providerID
        for item in snapshot.states {
            blocks[item.descriptor.id]?.update(state: item,
                                               isExpanded: expandedProviderID == item.descriptor.id)
        }
        onContentChanged?()
    }

    // MARK: - 派生（纯函数在 NetworkMonitorUI）
}

extension BillingPaneView {

    /// provider 状态快照 → Hero 输入（按注册顺序、同 provider 内按窗口声明顺序）
    static func heroInputs(from states: [BillingMonitor.ProviderState]) -> [BillingHeroInput] {
        states.flatMap { state in
            (state.balance?.percentLimits ?? []).map { limit in
                BillingHeroInput(providerName: state.descriptor.displayName,
                                 windowTitle: limit.title,
                                 remaining: limit.remainingFraction,
                                 resetsAt: limit.resetsAt)
            }
        }
    }

    static func hero(from states: [BillingMonitor.ProviderState]) -> BillingHeroValue? {
        BillingHeroLogic.lowestRemaining(heroInputs(from: states))
    }

    /// 页头时间戳：取全部 provider 里最近一次成功刷新
    static func latestStamp(_ states: [BillingMonitor.ProviderState]) -> String {
        guard let latest = states.compactMap(\.lastUpdated).max() else { return "—" }
        return BillingProviderBlockView.stamp(latest)
    }

    /// 当前数值单位档的展示文案（页脚状态带用）
    ///
    /// 取值来自 Core 侧的数值单位设置；本分支该 API 未合入，先返回 nil（状态带跳过该项）。
    static var unitLabel: String? { nil }
}
