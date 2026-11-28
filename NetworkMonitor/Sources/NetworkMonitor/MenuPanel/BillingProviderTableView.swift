import AppKit
import NetworkMonitorCore
import NetworkMonitorDesign
import NetworkMonitorFeatureBilling
import NetworkMonitorUI

// MARK: - provider 总表（页内唯一一张表）

/// provider 总表 —— 一行一家，用量型在上段、余额型在下段
///
/// 版式来自原型 F1「表为主」：
/// - 上段每行 34pt，左侧固定名称区、右侧均分 N 个窗口列（列数 = 全表最多窗口数，封顶 3）；
/// - 下段是纯余额型（DeepSeek / Moonshot / OpenRouter）：一行 22pt，金额贴右；
/// - 两段之间一条「余额型」分段线，只有存在余额型 provider 时才出现。
///
/// 点击任意一行进入该 provider 的覆盖式二级页（`BillingDetailPaneView`）。
/// 旧版「卡头就地展开用量区」路径已删除：展开会把下面几家推出屏幕，
/// 而 v2 的信息密度靠「一屏读完所有家」而不是「逐家展开」。
@MainActor
final class BillingProviderTableView: NSView {

    /// 点某一行：进入二级页
    var onOpenProvider: ((String) -> Void)?

    private let card = PaneCardBackgroundView()
    private let usageStack = NSStackView()
    private let balanceSplit = BillingTableSplitRow()
    private let balanceStack = NSStackView()
    /// 空态行（有 provider 但没有一个拿到数据时说明「为什么都是 —」）
    private let emptyHint = MenuPanelLabel.text("", font: PaneCardStyle.metaFont,
                                                color: PaneCardStyle.tertiaryText)

    private(set) var usageRows: [String: BillingProviderRowView] = [:]
    private(set) var balanceRows: [String: BillingBalanceRowView] = [:]
    /// 当前渲染顺序（键盘焦点顺序与之一致）
    private(set) var order: [String] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false

        usageStack.orientation = .vertical
        usageStack.alignment = .leading
        usageStack.spacing = 0
        balanceStack.orientation = .vertical
        balanceStack.alignment = .leading
        balanceStack.spacing = 0
        emptyHint.isHidden = true

        let body = NSStackView(views: [usageStack, balanceSplit, balanceStack, emptyHint])
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 2
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
        setAccessibilityRole(.group)
        setAccessibilityLabel("额度 Provider 总表")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 键盘可达行（与视觉顺序一致：用量型在上、余额型在下）
    var focusableRows: [MenuPanelRow] {
        order.compactMap { usageRows[$0] ?? balanceRows[$0] }
    }

    /// 当前渲染的行（验收与快照取证用）
    var rowCount: Int { order.count }

    // MARK: - 数据更新

    /// 应用一帧快照
    ///
    /// `states` 只含可见 provider（数据层契约），本视图不再过滤；
    /// 「谁进上段、谁进下段、列数几列」全部来自 `BillingAggregate` 纯函数。
    func update(states: [BillingMonitor.ProviderState]) {
        let rows = states.map(Self.tableRow)
        let columnCount = BillingAggregate.columnCount(rows)
        let usage = rows.filter { !$0.isBalanceOnly }
        let balances = rows.filter(\.isBalanceOnly)
        let hasData = states.contains { $0.balance.map { !$0.isEmpty } ?? false }

        sync(usage: usage, balances: balances, states: states, columnCount: columnCount)
        balanceSplit.isHidden = balances.isEmpty

        emptyHint.isHidden = hasData || states.isEmpty
        emptyHint.stringValue = hasData ? "" : "还没有拿到额度数据，点右上角刷新重试"

        order = usage.map(\.id) + balances.map(\.id)
    }

    /// 视图形状变化才重建（仅在 provider 集合或列数变化时）；纯数值刷新就地更新
    private func sync(usage: [BillingAggregate.ProviderRow],
                      balances: [BillingAggregate.ProviderRow],
                      states: [BillingMonitor.ProviderState],
                      columnCount: Int) {
        let usageIDs = usage.map(\.id)
        if Set(usageRows.keys) != Set(usageIDs) {
            rebuildUsage(usageIDs)
        }
        let balanceIDs = balances.map(\.id)
        if Set(balanceRows.keys) != Set(balanceIDs) {
            rebuildBalance(balanceIDs)
        }
        for row in usage {
            guard let state = states.first(where: { $0.descriptor.id == row.id }),
                  let view = usageRows[row.id] else { continue }
            view.update(row: row,
                        symbolName: state.descriptor.symbolName,
                        statusKind: Self.statusKind(state),
                        columnCount: columnCount)
        }
        for row in balances {
            guard let state = states.first(where: { $0.descriptor.id == row.id }),
                  let view = balanceRows[row.id] else { continue }
            let amount = state.balance?.totalAvailableUSD
            view.update(id: row.id,
                        name: row.name,
                        symbolName: state.descriptor.symbolName,
                        amount: Self.amountText(amount),
                        currency: amount == nil ? nil : Self.currencyText(state))
        }
    }

    private func rebuildUsage(_ ids: [String]) {
        for view in usageStack.arrangedSubviews {
            usageStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        usageRows.removeAll()
        for id in ids {
            let row = BillingProviderRowView()
            row.onOpen = { [weak self] in self?.onOpenProvider?(id) }
            usageStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: usageStack.widthAnchor).isActive = true
            usageRows[id] = row
        }
    }

    private func rebuildBalance(_ ids: [String]) {
        for view in balanceStack.arrangedSubviews {
            balanceStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        balanceRows.removeAll()
        for id in ids {
            let row = BillingBalanceRowView()
            row.onOpen = { [weak self] in self?.onOpenProvider?(id) }
            balanceStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: balanceStack.widthAnchor).isActive = true
            balanceRows[id] = row
        }
    }

    // MARK: - 纯映射（判据在 BillingAggregate，这里只做字段搬运）

    /// provider 状态 -> 总表行
    ///
    /// 余额型判据 = 没有任何百分比窗口（DeepSeek / Moonshot / OpenRouter 都只报金额）；
    /// 其余走上段窗口列，窗口超过 3 个时取前 3（`BillingAggregate.padded` 再按全表列数补齐）。
    static func tableRow(_ state: BillingMonitor.ProviderState) -> BillingAggregate.ProviderRow {
        let limits = state.balance?.percentLimits ?? []
        let windows = limits.map { limit in
            BillingAggregate.WindowColumn(title: limit.title,
                                          remaining: limit.remainingFraction,
                                          resetsAt: limit.resetsAt,
                                          badge: limit.badge)
        }
        return BillingAggregate.ProviderRow(id: state.descriptor.id,
                                            name: Self.primaryName(state.descriptor),
                                            subtitle: state.descriptor.instanceLabel,
                                            windows: windows,
                                            isBalanceOnly: windows.isEmpty)
    }

    /// 主名（去掉实例后缀）：同名多实例时名称列只放主名，实例标签进副标
    /// （否则 96pt 的名称列会把 «Open Design (home)» 截成 «Open Design…»，两个实例看起来一样）
    static func primaryName(_ descriptor: BillingMonitor.ProviderDescriptor) -> String {
        guard let label = descriptor.instanceLabel, !label.isEmpty else {
            return descriptor.displayName
        }
        let suffix = " (" + label + ")"
        guard descriptor.displayName.hasSuffix(suffix) else { return descriptor.displayName }
        return String(descriptor.displayName.dropLast(suffix.count))
    }

    /// 状态胶囊语义档（与旧卡头同一判据）
    static func statusKind(_ state: BillingMonitor.ProviderState) -> BillingStatusKind {
        BillingProviderStatusLogic.kind(
            errorMessage: state.errorMessage,
            remainingFractions: (state.balance?.percentLimits ?? []).compactMap(\.remainingFraction),
            isLoading: state.isLoading,
            hasBalance: state.balance.map { !$0.isEmpty } ?? false)
    }

    /// 金额文案（nil = 无限制 Key）
    static func amountText(_ amount: Double?) -> String? {
        guard let amount else { return nil }
        return formatExactNumber(amount)
    }

    /// 币种文案（CNY 显示中文元符号以外的三字母码，与原型一致）
    static func currencyText(_ state: BillingMonitor.ProviderState) -> String {
        state.balance?.currencyCode ?? "USD"
    }
}

// MARK: - 「余额型」分段行

/// 分段行 —— 左侧「余额型」小标题 + 右侧横线（原型 F1 的 bsplit）
@MainActor
final class BillingTableSplitRow: NSView {

    private let title = MenuPanelLabel.text("余额型", font: PaneCardStyle.axisFont,
                                             color: PaneCardStyle.tertiaryText)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        let line = BillingSplitLineView()
        let stack = NSStackView(views: [title, line])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 14),
            line.heightAnchor.constraint(equalToConstant: 1),
        ])
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("余额型 Provider")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}

/// 分段横线（1pt 发丝线，主题 hairline）
@MainActor
final class BillingSplitLineView: NSView {

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        PaneCardStyle.hairline.setFill()
        bounds.fill()
    }
}