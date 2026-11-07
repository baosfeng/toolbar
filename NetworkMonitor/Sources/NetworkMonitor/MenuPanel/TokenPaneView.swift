import AppKit
import NetworkMonitorCore

// MARK: - Token 页（定稿原型 final-定稿.html 的 Swift 实现）

/// Token 消耗页 —— 菜单面板第 5 个 tab
///
/// 数据由 HarnessUsageSnapshot 注入（update），本视图不直接访问数据库或索引服务。
/// 版式对齐定稿原型：四族卡（sparkline + 同比）→ 小时/按天主图（今日/昨日、堆叠/对比、
/// 累计虚线、每根柱可点）→ 天趋势（固定 14 天）→ 缓存命中环 → 项目/模型双栏 →
/// 今日 vs 昨日对比条 → 状态带。任一密度块可点进面板内覆盖式二级页（共六个）。
/// 成员可见性：布局装配在 TokenPaneView+Layout.swift，渲染在 +Render.swift，
/// 二级页在 TokenDetailPages*.swift。
final class TokenPaneView: MenuPanelPaneView {

    // MARK: - 回调

    var onRefresh: (() -> Void)?
    var onContentChanged: (() -> Void)?

    // MARK: - 交互状态

    private(set) var range: TokenRange = .today
    private(set) var hourScope: TokenHourScope = .today
    private(set) var hourView: TokenHourView = .stack
    private(set) var metric: TokenChartMetric = .total
    private(set) var trendMode: TokenTrendMode = .stack
    /// 当前打开的二级页（nil = 主面板）
    private(set) var detailKind: TokenDetailKind?
    private(set) var selection: TokenBucketSelection?

    // MARK: - 数据

    /// 最近一帧快照（渲染 / 二级页共用，跨文件访问故为 internal）
    var snapshot: HarnessUsageSnapshot?
    var lastModel: TokenPaneModel?

    // MARK: - 页头与范围

    let rangeControl = TokenSegmentedControl(titles: TokenRange.allCases.map { $0.title })
    let refreshRow = TokenIconButtonRow(symbolName: "arrow.clockwise")
    let indexLabel = MenuPanelLabel.text("", font: TokenPaneStyle.metaFont,
                                        color: TokenPaneStyle.tertiaryText)
    let hostLabel = MenuPanelLabel.text("", font: TokenPaneStyle.pageHeadFont,
                                        color: TokenPaneStyle.secondaryText)

    // MARK: - 分区

    /// 首屏 Hero（当前范围三项合计 + 较昨日 + 实时）
    let heroView = TokenHeroView()
    lazy var familyCards = TokenMetric.allCases.map { metric in
        TokenFamilyCardView(metric: metric, onClick: {})
    }
    let hourCard = TokenCardRow(height: 88, background: TokenPaneStyle.cardFill)
    let hourTitle = MenuPanelLabel.text("", font: TokenPaneStyle.cardHeadTitleFont,
                                        color: TokenPaneStyle.secondaryText)
    let hourMeta = MenuPanelLabel.text("", font: TokenPaneStyle.metaNumberFont,
                                       color: TokenPaneStyle.tertiaryText)
    let hourAction = TokenTextButton(title: "切：请求数")
    let daySegment = TokenSegmentedControl(titles: TokenHourScope.allCases.map { $0.title })
    /// 主图形态切换（堆叠 / 对比）——收成单按钮，省掉第二个分段控件的宽度
    let viewAction = TokenTextButton(title: "切：对比")
    let hourBars = TokenBarsView()
    let hourAxis = TokenAxisView()
    let hourLegend = TokenLegendRowView()

    let trendCard = TokenCardRow(height: 38, background: TokenPaneStyle.cardFill)
    let trendTitle = MenuPanelLabel.text("天趋势 · 固定 14 天", font: TokenPaneStyle.cardHeadTitleFont,
                                         color: TokenPaneStyle.secondaryText)
    let trendMeta = MenuPanelLabel.text("", font: TokenPaneStyle.metaNumberFont,
                                        color: TokenPaneStyle.tertiaryText)
    let trendAction = TokenTextButton(title: "切：分线")
    let trendSpark = TokenSparkView(height: TokenPaneStyle.trendHeight,
                                    stroke: TokenPaneStyle.uncachedColor,
                                    fill: TokenPaneStyle.uncachedColor)

    let cacheCard = TokenCardRow(height: 54, background: TokenPaneStyle.cardFill)
    let cacheRing = TokenRingView()
    let cacheMeta = MenuPanelLabel.text("", font: TokenPaneStyle.metaNumberFont,
                                        color: TokenPaneStyle.tertiaryText)
    let cacheLegend = TokenLegendRowView()

    let projectCard = TokenCardRow(height: 111, background: TokenPaneStyle.cardFill)
    let modelCard = TokenCardRow(height: 111, background: TokenPaneStyle.cardFill)
    let projectBar = TokenStackBarView()
    let modelBar = TokenStackBarView()
    lazy var projectRows = (0..<3).map { _ in TokenDistroRowView() }
    lazy var modelRows = (0..<3).map { _ in TokenDistroRowView() }
    let projectMeta = MenuPanelLabel.text("", font: TokenPaneStyle.metaNumberFont,
                                          color: TokenPaneStyle.tertiaryText)
    let modelMeta = MenuPanelLabel.text("", font: TokenPaneStyle.metaNumberFont,
                                        color: TokenPaneStyle.tertiaryText)

    let compareCard = TokenCardRow(height: 50, background: TokenPaneStyle.cardFill)
    let compareTotal = MenuPanelLabel.text("", font: TokenPaneStyle.metaNumberFont,
                                           color: TokenPaneStyle.tertiaryText)
    let compareDelta = MenuPanelLabel.text("", font: TokenPaneStyle.yoyFont,
                                           color: TokenPaneStyle.warnInk)
    let compareCurrentRow = TokenCompareRowView()
    let comparePreviousRow = TokenCompareRowView()

    let stateBand = TokenStateBandView()

    /// 二级页容器（覆盖在主面板之上，同一 Pane 内切换）
    let detailPane = TokenDetailPaneView()

    // MARK: - 状态页

    let dataStack = NSStackView()
    /// 四族卡矩阵容器（2×2）
    let familyGrid = NSStackView()
    /// 页头下方的内容起点（buildHeader 里赋值为范围条底边）
    var contentTopAnchor: NSLayoutYAxisAnchor?
    let loadingView = TokenLoadingView()
    lazy var emptyView = TokenEmptyView(onRetry: { [weak self] in self?.onRefresh?() })
    let unavailableView = TokenUnavailableView()

    // MARK: - 初始化

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        buildHeader()
        buildSections()
        wireActions()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    // MARK: - 键盘可达

    override var focusableRows: [MenuPanelRow] {
        guard detailKind == nil else { return [] }
        var rows: [MenuPanelRow] = [refreshRow]
        rows.append(contentsOf: rangeControl.focusableRows)
        if !dataStack.isHidden {
            rows.append(contentsOf: daySegment.focusableRows)
            rows.append(contentsOf: familyCards)
            rows.append(hourCard)
            rows.append(trendCard)
            rows.append(cacheCard)
            rows.append(projectCard)
            rows.append(modelCard)
        }
        if !emptyView.isHidden { rows.append(emptyView.retryRow) }
        return rows
    }

    // MARK: - 数据更新

    func update(_ snapshot: HarnessUsageSnapshot) {
        self.snapshot = snapshot
        applyState()
    }

    // MARK: - 状态切换

    private func applyState() {
        guard let snapshot else { return }
        let available = snapshot.sourceAvailability.isAvailable
        let empty = TokenComparison.isEmpty(snapshot)
        let indexing = snapshot.indexingState.isIndexing
        let progress: HarnessIndexProgress? = {
            if case .indexing(let progress) = snapshot.indexingState { return progress }
            return nil
        }()

        unavailableView.isHidden = available
        guard available else {
            unavailableView.update(message: snapshot.sourceAvailability.displayMessage)
            dataStack.isHidden = true
            loadingView.isHidden = true
            emptyView.isHidden = true
            indexLabel.isHidden = true
            detailPane.isHidden = true
            detailKind = nil
            onContentChanged?()
            return
        }

        // 首轮索引尚未产出任何数据：显示带进度的加载态，不阻塞面板
        if empty && (indexing || snapshot.indexingState == .idle) {
            loadingView.update(progress: progress)
            loadingView.isHidden = false
            dataStack.isHidden = true
            emptyView.isHidden = true
            indexLabel.isHidden = true
            detailPane.isHidden = true
            detailKind = nil
            onContentChanged?()
            return
        }

        loadingView.isHidden = true
        dataStack.isHidden = empty
        emptyView.isHidden = !empty
        if empty {
            indexLabel.isHidden = true
            detailPane.isHidden = true
            detailKind = nil
            onContentChanged?()
            return
        }
        indexLabel.isHidden = !indexing
        if indexing, let progress {
            indexLabel.stringValue = "索引中 \(progress.completedFiles)/\(progress.totalFiles) · 完成后自动刷新"
        }
        render()
    }

    // MARK: - 二级页

    func openDetail(_ kind: TokenDetailKind, selection: TokenBucketSelection? = nil) {
        guard let snapshot, let model = lastModel else { return }
        self.detailKind = kind
        self.selection = selection
        detailPane.update(kind: kind, model: model, snapshot: snapshot,
                          selection: selection, hourScope: hourScope)
        // 打开即挂悬停文案：否则要等下一次数据刷新才生效（占比条 / 图例是这里唯一的 provider 出口）
        syncDistroHoverTips(kind: kind, model: model)
        detailPane.isHidden = false
        dataStack.isHidden = true
        onContentChanged?()
    }

    func closeDetail() {
        guard detailKind != nil else { return }
        detailKind = nil
        selection = nil
        detailPane.isHidden = true
        dataStack.isHidden = false
        render()
    }

    // MARK: - 动作

    private func wireActions() {
        refreshRow.onClick = { [weak self] in self?.onRefresh?() }
        rangeControl.onSelect = { [weak self] index in
            guard let self, let value = TokenRange(rawValue: index) else { return }
            self.range = value
            self.render()
        }
        daySegment.onSelect = { [weak self] index in
            guard let self, let value = TokenHourScope(rawValue: index) else { return }
            self.hourScope = value
            self.render()
        }
        viewAction.onClick = { [weak self] in
            guard let self else { return }
            self.hourView = self.hourView == .stack ? .compare : .stack
            self.render()
        }
        hourAction.onClick = { [weak self] in
            guard let self else { return }
            self.metric = self.metric == .total ? .request : .total
            self.render()
        }
        trendAction.onClick = { [weak self] in
            guard let self else { return }
            self.trendMode = self.trendMode == .stack ? .line : .stack
            self.render()
        }
        for card in familyCards {
            card.onClick = { [weak self] in self?.openDetail(.hourly) }
        }
        hourCard.onClick = { [weak self] in self?.openDetail(.hourly) }
        hourBars.onSelect = { [weak self] index in
            guard let self else { return }
            self.openDetail(.bucket,
                            selection: TokenBucketSelection(index: index,
                                                           isHour: self.range == .today,
                                                           scope: self.hourScope))
        }
        trendCard.onClick = { [weak self] in self?.openDetail(.trend) }
        cacheCard.onClick = { [weak self] in self?.openDetail(.cache) }
        projectCard.onClick = { [weak self] in self?.openDetail(.projects) }
        modelCard.onClick = { [weak self] in self?.openDetail(.models) }
        detailPane.onBack = { [weak self] in self?.closeDetail() }
        detailPane.onSelectBucket = { [weak self] selection in
            self?.openDetail(.bucket, selection: selection)
        }
    }

#if DEBUG
    /// 快照自证专用（仅 DEBUG）：切换范围 / 小时归属 / 趋势形态 / 主图形态（堆叠·对比）
    func applyStateForSnapshot(range: TokenRange, hourScope: TokenHourScope, trendMode: TokenTrendMode,
                               hourView: TokenHourView? = nil, metric: TokenChartMetric? = nil) {
        self.range = range
        self.hourScope = hourScope
        self.trendMode = trendMode
        if let hourView { self.hourView = hourView }
        if let metric { self.metric = metric }
        if snapshot != nil { render() }
    }

    /// 快照自证专用（仅 DEBUG）：打开指定二级页（取证用）
    func openDetailForSnapshot(_ kind: TokenDetailKind, selection: TokenBucketSelection? = nil) {
        openDetail(kind, selection: selection)
    }

#endif
}