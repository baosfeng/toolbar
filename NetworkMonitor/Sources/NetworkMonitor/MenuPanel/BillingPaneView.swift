import AppKit
import NetworkMonitorCore

// MARK: - 额度页（聚合视图）

/// 额度页 — 一次展示全部 provider 的额度块，点块标题就地展开用量明细
///
/// 数据由 `BillingMonitor` 通过 `update(_:)` 注入；本视图不直接访问网络或凭据存储。
/// 键盘可达行顺序：刷新 → 块 1 标题 → 块 1 范围按钮 / 配置输入 → …（与视觉顺序一致）。
final class BillingPaneView: MenuPanelPaneView {

    // MARK: - 回调

    /// 点「刷新」（force 刷新）
    var onRefresh: (() -> Void)?
    /// 点错误条「重试」
    var onRetry: (() -> Void)?
    /// 切换某个 provider 的用量范围（参数：范围、provider id）
    var onRangeChange: ((BillingRange, String) -> Void)?
    /// 未配置块点「去设置配置」：打开设置窗口并选中额度 Provider 页
    var onOpenSettings: (() -> Void)?
    /// 展开 / 收起导致内容高度变化
    var onContentChanged: (() -> Void)?

    // MARK: - 子视图

    private let emptyView = BillingEmptyView()
    private let headerStack = NSStackView()
    private let titleLabel = MenuPanelLabel.text("额度", font: BillingPaneStyle.cardTitleFont,
                                                 color: BillingPaneStyle.secondaryText)
    private let timeLabel = MenuPanelLabel.text("—", font: BillingPaneStyle.stampFont,
                                                color: BillingPaneStyle.tertiaryText)
    private let refreshRow = BillingIconButtonRow(symbolName: "arrow.clockwise")
    private let blockStack = NSStackView()

    /// 按 provider id 缓存的块视图
    private var blocks: [String: BillingProviderBlockView] = [:]
    /// 块的排列顺序（用于判断是否需要重建）
    private var blockOrder: [String] = []
    /// 当前展开的 provider（nil = 全部收起）
    private var expandedProviderID: String?
    /// 最近一次快照（切换展开态时按它重渲染）
    private var snapshot: BillingMonitor.Snapshot?

    // MARK: - 初始化

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        timeLabel.alignment = .right
        refreshRow.onClick = { [weak self] in self?.onRefresh?() }
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)

        headerStack.orientation = .horizontal
        headerStack.alignment = .centerY
        headerStack.spacing = 6
        headerStack.addArrangedSubview(titleLabel)
        headerStack.addArrangedSubview(MenuPanelLabel.spacer())
        headerStack.addArrangedSubview(timeLabel)
        headerStack.addArrangedSubview(refreshRow)

        blockStack.orientation = .vertical
        blockStack.alignment = .leading
        blockStack.spacing = 7

        emptyView.isHidden = true

        let root = NSStackView(views: [emptyView, headerStack, blockStack])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 8
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor),
            root.trailingAnchor.constraint(equalTo: trailingAnchor),
            root.topAnchor.constraint(equalTo: topAnchor),
            root.bottomAnchor.constraint(equalTo: bottomAnchor),
            headerStack.heightAnchor.constraint(greaterThanOrEqualToConstant: 20),
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
    }

    /// 快照自证专用（仅 DEBUG）：强制悬停某个 provider 用量柱状图的第 index 根柱
    func forceChartHoverForSnapshot(_ index: Int?) {
        guard let snapshot else { return }
        for state in snapshot.states where expandedProviderID == state.descriptor.id {
            blocks[state.descriptor.id]?.usageSection.forceHoverForSnapshot(index)
        }
    }
#endif

    // MARK: - 键盘可达

    override var focusableRows: [MenuPanelRow] {
        guard let snapshot, !snapshot.states.isEmpty else { return [] }
        var rows: [MenuPanelRow] = [refreshRow]
        for state in snapshot.states {
            if let block = blocks[state.descriptor.id] {
                rows.append(contentsOf: block.focusableRows)
            }
        }
        return rows
    }

    // MARK: - 数据更新

    /// 应用最新快照（由控制器转发）
    func update(_ snapshot: BillingMonitor.Snapshot) {
        self.snapshot = snapshot
        let hasProvider = !snapshot.states.isEmpty
        emptyView.isHidden = hasProvider
        headerStack.isHidden = !hasProvider
        blockStack.isHidden = !hasProvider
        // 展开的 provider 被移除（注册表变化）时复位，避免指向不存在的块
        if let expanded = expandedProviderID,
           !snapshot.states.contains(where: { $0.descriptor.id == expanded }) {
            expandedProviderID = nil
        }
        guard hasProvider else { return }
        syncBlocks(snapshot.states)
        timeLabel.stringValue = Self.latestStamp(snapshot.states)
        for state in snapshot.states {
            blocks[state.descriptor.id]?.update(state: state,
                                                isExpanded: expandedProviderID == state.descriptor.id)
        }
    }

    /// 按 provider 顺序重建块视图（仅在注册集合变化时）
    private func syncBlocks(_ states: [BillingMonitor.ProviderState]) {
        let ids = states.map { $0.descriptor.id }
        guard blockOrder != ids else { return }
        for view in blockStack.arrangedSubviews {
            blockStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        blocks.removeAll()
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

    /// 展开 / 收起某个 provider 的用量区（同一时刻只允许一个展开）
    private func toggleExpand(_ providerID: String) {
        guard let snapshot, let state = snapshot.state(for: providerID) else { return }
        // 未配置块没有可展开内容：配置入口是块内的「去设置配置」
        guard state.isConfigured else { return }
        expandedProviderID = (expandedProviderID == providerID) ? nil : providerID
        for item in snapshot.states {
            blocks[item.descriptor.id]?.update(state: item,
                                               isExpanded: expandedProviderID == item.descriptor.id)
        }
        onContentChanged?()
    }

    // MARK: - 文案

    /// 页头时间戳：取全部 provider 里最近一次成功刷新
    private static func latestStamp(_ states: [BillingMonitor.ProviderState]) -> String {
        guard let latest = states.compactMap(\.lastUpdated).max() else { return "—" }
        return BillingProviderBlockView.stamp(latest)
    }
}