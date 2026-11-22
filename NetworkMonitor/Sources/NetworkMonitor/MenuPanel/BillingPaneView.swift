import AppKit
import NetworkMonitorCore
import NetworkMonitorDesign
import NetworkMonitorFeatureBilling
import NetworkMonitorUI

// MARK: - 额度页（聚合视图 · 与 Token 页同族）

/// 额度页 —— 页头 + Hero（最低剩余）+ provider 总表 + 图表区 + 页脚状态带
///
/// v2 版式（原型 F1「表为主」+ 补图表）：
/// 1. 页头 22pt（复用 PaneHeaderRowView「额度」+ 时间 + 刷新）；
/// 2. Hero 46pt（最低剩余窗口）；
/// 3. provider 总表：一行一家（窗口百分比列），余额型走表下段金额行；
/// 4. 图表区：页内唯一一条 24h/7d/30d 分段，控制 7 天柱图 + 模型 Top4 + 30 天走势；
/// 5. 页脚状态带 20pt。
///
/// 点任意一行 → 面板内覆盖式二级页（该家完整用量）。旧版「卡头就地展开用量区」与
/// 「每家一套范围分段」已删除：前者把下面几家推出屏幕，后者让切一次范围要点 N 次。
/// 内容高过面板可视高度时由面板根视图的 NSScrollView 正常滚动，不裁切、不压缩。
final class BillingPaneView: MenuPanelPaneView {

    // MARK: - 回调

    /// 刷新（页头按钮 / 二级页重试）
    var onRefresh: (() -> Void)?
    var onRetry: (() -> Void)?
    /// 页级范围切换（第二参数是首家支持用量的 provider id：数据层按 provider 拉取用量）
    var onRangeChange: ((BillingRange, String) -> Void)?
    var onOpenSettings: (() -> Void)?
    var onContentChanged: (() -> Void)?

    // MARK: - 子视图

    /// 页头行（额度 → 最近刷新时间 → 刷新），页名与 22pt 高度由共用视图自带
    private let headerView = PaneHeaderRowView(title: "额度")
    private let refreshRow = BillingIconButtonRow(symbolName: "arrow.clockwise")
    private let heroView = BillingHeroView()
    /// 放宽为 internal：BillingPanePreview 的 DEBUG 取证要读行高读数
    let tableView = BillingProviderTableView()
    private let chartsView = BillingChartsSectionView()
    private let detailView = BillingDetailPaneView()
    private let stateBand = PaneStateBandView()
    private let emptyView = BillingEmptyView()

    /// 首屏（页头 + Hero + 总表 + 图表 + 状态带）与二级页互斥
    private let overviewStack = NSStackView()
    private let rootStack = NSStackView()

    private var snapshot: BillingMonitor.Snapshot?
    /// 页级范围（默认 7 天：原型首屏就是 7 天柱图）
    private(set) var range: BillingRange = .last7Days
    /// 当前二级页的 provider（nil = 首屏）
    private(set) var detailProviderID: String?

    /// 是否正在看二级页（面板根视图的 Esc 分流据此先返回主表）
    var isShowingDetail: Bool { detailProviderID != nil }

    // MARK: - 初始化

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        refreshRow.onClick = { [weak self] in self?.onRefresh?() }
        // 页头走五页共用的 PaneHeaderRowView：页名「额度」由视图自带，
        // 右侧最近刷新时间走 updateMeta、刷新按钮走动作槽，页头不再各页自己拼一条栈
        headerView.updateMeta("—")
        headerView.setTrailing([refreshRow])

        tableView.onOpenProvider = { [weak self] providerID in self?.showDetail(providerID) }
        chartsView.onRangeChange = { [weak self] range in self?.applyRange(range) }
        detailView.onBack = { [weak self] in self?.showOverview() }
        detailView.onRetry = { [weak self] in self?.onRetry?() }

        emptyView.isHidden = true
        emptyView.onConfigure = { [weak self] in self?.onOpenSettings?() }
        detailView.isHidden = true

        for subview in [headerView, heroView, tableView, chartsView, stateBand, emptyView] {
            overviewStack.addArrangedSubview(subview)
        }
        overviewStack.orientation = .vertical
        overviewStack.alignment = .leading
        overviewStack.spacing = PaneCardStyle.cardSpacing

        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = PaneCardStyle.cardSpacing
        rootStack.addArrangedSubview(overviewStack)
        rootStack.addArrangedSubview(detailView)
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            rootStack.topAnchor.constraint(equalTo: topAnchor),
            rootStack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        for view in rootStack.arrangedSubviews {
            view.widthAnchor.constraint(equalTo: rootStack.widthAnchor).isActive = true
        }
        for view in overviewStack.arrangedSubviews {
            view.widthAnchor.constraint(equalTo: overviewStack.widthAnchor).isActive = true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    // MARK: - 二级页导航

    /// 进入某家的覆盖式二级页（面板内切换，不弹窗、不加 tab）
    func showDetail(_ providerID: String) {
        guard let snapshot, let state = snapshot.state(for: providerID) else { return }
        detailProviderID = providerID
        detailView.isHidden = false
        overviewStack.isHidden = true
        // 用当前帧数据立即填充，不等下一次刷新
        detailView.update(state: state, columnCount: Self.columnCount(snapshot.states))
        onContentChanged?()
    }

    /// 返回首屏（Esc 与「返回额度」按钮共用）
    func showOverview() {
        guard detailProviderID != nil else { return }
        detailProviderID = nil
        detailView.isHidden = true
        overviewStack.isHidden = false
        onContentChanged?()
    }

    /// 二级页跟随最新快照
    private func syncDetail() {
        guard let snapshot, let id = detailProviderID,
              let state = snapshot.state(for: id) else { return }
        detailView.update(state: state, columnCount: Self.columnCount(snapshot.states))
    }

    // MARK: - 键盘可达

    override var focusableRows: [MenuPanelRow] {
        guard let snapshot, !snapshot.states.isEmpty else {
            return emptyView.focusableRows
        }
        if isShowingDetail { return [refreshRow] + detailView.focusableRows }
        return [refreshRow] + tableView.focusableRows + chartsView.focusableRows
    }

    // MARK: - 数据更新

    func update(_ snapshot: BillingMonitor.Snapshot) {
        self.snapshot = snapshot
        let hasProvider = !snapshot.states.isEmpty
        emptyView.isHidden = hasProvider
        // 二级页打开时保持二级页可见；provider 消失则退回主表，避免停在已不存在的数据上
        if let detail = detailProviderID,
           !snapshot.states.contains(where: { $0.descriptor.id == detail }) {
            detailProviderID = nil
            detailView.isHidden = true
        }
        overviewStack.isHidden = !hasProvider || isShowingDetail
        stateBand.isHidden = !hasProvider
        guard hasProvider else {
            // 空态文案随数据层给的原因分支（无启用 provider / 有启用但全未配置）
            emptyView.update(reason: Self.emptyReason(snapshot.emptyReason))
            return
        }

        tableView.update(states: snapshot.states)
        chartsView.update(states: snapshot.states, range: range)
        if isShowingDetail { syncDetail() }

        let stamp = Self.latestStamp(snapshot.states)
        headerView.updateMeta(stamp)
        // 暂停态更要说清「为什么不动」：否则用户只看到时间戳停住（这正是「额度没用了」的现场）
        heroView.update(hero: Self.hero(from: snapshot.states),
                        clock: BillingRefreshStatusLogic.clockText(isPaused: false, latestStamp: stamp),
                        isPaused: snapshot.isPaused)
        // 四项统一带 tone 位：混用二元 / 三元组会让数组元素类型推断失败
        let throttled = Self.throttledCount(snapshot.states)
        stateBand.update(items: [
            (key: "数量", value: String(snapshot.states.count), tone: nil),
            (key: "刷新", value: stamp, tone: nil),
            (key: "限流", value: String(throttled),
             tone: throttled > 0 ? PaneCardStyle.warnInk : nil),
            (key: "状态", value: BillingRefreshStatusLogic.bandText(isPaused: snapshot.isPaused),
             tone: BillingRefreshStatusLogic.bandWarns(isPaused: snapshot.isPaused)
                 ? PaneCardStyle.warnInk : nil),
        ])
    }

    /// 切换页级范围：整块图表立即重算；同时让数据层按该范围重拉用量
    ///
    /// 只重拉首家支持用量的 provider：页级分段控制的是整块图表的汇总口径，
    /// 数据层接口按 provider 拉取，全部重拉会瞬间打出 N 个请求。
    private func applyRange(_ newRange: BillingRange) {
        guard range != newRange else { return }
        range = newRange
        if let snapshot {
            chartsView.update(states: snapshot.states, range: newRange)
        }
        // 逐家通知：providers 各自持有自己的 usage.range，只改一家会让其余家停在旧范围，
        // 图表汇总按 range 过滤时就会漏算（画出来比实际少）
        for state in snapshot?.states ?? [] where state.descriptor.supportsUsage {
            onRangeChange?(newRange, state.descriptor.id)
        }
        onContentChanged?()
    }

    // MARK: - 派生（纯函数在 NetworkMonitorUI）

    /// 全表列数（主表与二级页共用，切换页面时段落不跳）
    static func columnCount(_ states: [BillingMonitor.ProviderState]) -> Int {
        BillingAggregate.columnCount(states.map(BillingProviderTableView.tableRow))
    }

    /// 限流家数（页脚状态带）
    static func throttledCount(_ states: [BillingMonitor.ProviderState]) -> Int {
        BillingAggregate.throttledCount(states.map(BillingProviderTableView.tableRow))
    }
}

#if DEBUG
extension BillingPaneView {

    /// 快照自证专用（仅 DEBUG）：进入指定 provider 的二级页（nil = 回主表）
    ///
    /// 保留旧名 expandForPreview：Debug 目录的取证脚本不在本任务 write scope 内，
    /// 改名会让它们编译失败；语义已从「展开用量区」变为「进入二级页」。
    func expandForPreview(_ providerID: String?) {
        if let providerID, snapshot?.state(for: providerID) != nil {
            showDetail(providerID)
        } else {
            showOverview()
        }
    }

    /// 快照自证专用（仅 DEBUG）：强制悬停某根柱（二级页内）
    func forceChartHoverForSnapshot(_ index: Int?) {
        detailView.forceHoverForSnapshot(index)
    }
}
#endif

extension BillingPaneView {

    /// provider 状态快照 → Hero 输入（按注册顺序、同 provider 内按窗口声明顺序）
    static func heroInputs(from states: [BillingMonitor.ProviderState]) -> [BillingHeroInput] {
        states.flatMap { state in
            (state.balance?.percentLimits ?? []).map { limit in
                BillingHeroInput(providerName: state.descriptor.displayName,
                                 windowTitle: limit.title,
                                 // 不可得窗口不进 Hero 比较（Hero 无数据时显示「—」）
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
        return BillingTimeFormat.string(latest)
    }

    /// 当前数值单位档的展示文案（页脚状态带用）
    ///
    /// 取值来自 Core 的 NumberUnitPreferences（设置页「显示 › 数值单位」写入）。
    static var unitLabel: String? { NumberUnitPreferences().style.title }

    /// 数据层空态原因 → 视图文案原因
    ///
    /// 数据层只分两类（无启用 provider / 有启用但都没凭据），视图层文案多一类「注册表为空」的措辞；
    /// 这里做唯一映射，别在视图里再判一遍。
    static func emptyReason(_ reason: BillingMonitor.BillingEmptyReason?) -> BillingEmptyReason {
        guard let reason else { return .unknown }
        switch reason {
        case .noEnabledProvider: return .allDisabled
        case .noneConfigured:    return .allUnconfigured
        }
    }
}
