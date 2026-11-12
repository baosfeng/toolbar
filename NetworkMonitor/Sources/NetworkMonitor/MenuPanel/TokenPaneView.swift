import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - Token 页

/// Token 消耗页 —— 菜单面板第 5 个 tab
///
/// 数据由 HarnessUsageSnapshot 注入（update），本视图不直接访问数据库或索引服务。
/// 版式（改前 8 个区块一屏到底，520pt 内既看不到图表也看不到分布）：
/// 页头（主机 + 范围 + 刷新）→ 屏切换条（概览 / 用量 / 缓存 / 排行）→ 当前屏内容。
/// 区块归属由 TokenScreen 契约给出（NetworkMonitorUI，纯逻辑可断言）；各屏高度不同，
/// 切屏后走 onContentChanged 让面板重算 popover 尺寸。
/// 二级页保留三个（单桶 / 按小时三段 / 天趋势）；「缓存命中 / 按项目 / 按模型」
/// 已并入缓存屏与排行屏，入口与枚举 case 一并删除。
/// 成员分布：状态机与二级页在 +State.swift，布局在 +Layout.swift，渲染在 +Render.swift，
/// 屏内容在 TokenScreenContent*.swift，二级页在 TokenDetailPages*.swift。
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
    /// 当前屏 —— 区块归属见 TokenScreen 契约
    private(set) var screen: TokenScreen = .overview
    /// 当前打开的二级页（nil = 主面板）
    ///
    /// 写入方在 TokenPaneView+State.swift（applyStateMachine / openDetail），跨文件访问故放开 private(set)
    var detailKind: TokenDetailKind?
    var selection: TokenBucketSelection?

    // MARK: - 数据

    /// 最近一帧快照（渲染 / 二级页共用，跨文件访问故为 internal）
    var snapshot: HarnessUsageSnapshot?
    var lastModel: TokenPaneModel?

    // MARK: - 页头

    /// 范围分段（窗口边界按 Asia/Shanghai 切分，页头时区提示里写明）
    let rangeControl = TokenSegmentedControl(titles: TokenRange.allCases.map { $0.title })
    /// 屏切换条（页头下一行，四段等宽）
    let screenControl = TokenSegmentedControl(titles: TokenScreen.titles, expands: true)
    let refreshRow = TokenIconButtonRow(symbolName: "arrow.clockwise")
    let indexLabel = MenuPanelLabel.text("", font: TokenPaneStyle.metaFont,
                                        color: TokenPaneStyle.tertiaryText)
    /// 页名（页头左侧；与 Core 给的 hostLabel 前缀同源，口径文字去重时用）
    static let pageTitle = "DSH"
    /// 页头行（页名 → 会话数 → 范围分段 → 刷新），右侧口径文字与时区提示都挂在这条上
    let headerView = PaneHeaderRowView(title: TokenPaneView.pageTitle)

    // MARK: - 分区

    /// 概览屏 Hero（当前范围三项合计 + 较昨日 + 实时）
    let heroView = TokenHeroView()
    lazy var familyCards = TokenMetric.allCases.map { metric in
        TokenFamilyCardView(metric: metric, onClick: {})
    }
    /// 四族卡矩阵容器（2×2）
    let familyGrid = NSStackView()
    /// 屏页脚状态带：概览 / 用量 / 排行各一个实例，都用同一份 model.stateBand 更新
    ///
    /// 用的是五页共用的 `PaneStateBandView`（底 / 高度 / 内边距 / 圆角 / 键值字号走
    /// `PaneBandChrome`）；Token 页此前那份 `TokenStateBandView` 已删除，只保留语气色映射。
    let overviewBand = PaneStateBandView()
    let usageBand = PaneStateBandView()
    let rankingBand = PaneStateBandView()
    /// 三个状态带实例（渲染时统一刷新；缓存屏页脚是口径说明，没有状态带）
    var stateBands: [PaneStateBandView] { [overviewBand, usageBand, rankingBand] }

    /// 用量屏：主图卡（整屏独占，柱高 160pt + 左侧刻度与网格；每根柱可点进单桶页）
    let hourCard = TokenCardRow(height: 230, background: TokenPaneStyle.cardFill)
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

    /// 概览屏：缓存命中紧凑条（小环 + 命中率大字 + 三个值，数据取 model.cachePage）
    lazy var cacheHitStrip = TokenCacheHitStripView(onClick: { [weak self] in
        self?.selectScreen(.cache)
    })

    /// 概览屏：近 14 天迷你走势（56pt 高，补概览密度；整高的天趋势卡在用量屏）
    let overviewTrendCard = TokenCardRow(height: 79, background: TokenPaneStyle.cardFill)
    let overviewTrendTitle = MenuPanelLabel.text("近 14 天 · 固定",
                                                 font: TokenPaneStyle.cardHeadTitleFont,
                                                 color: TokenPaneStyle.secondaryText)
    let overviewTrendMeta = MenuPanelLabel.text("", font: TokenPaneStyle.metaNumberFont,
                                                color: TokenPaneStyle.tertiaryText)
    let overviewTrendSpark = TokenSparkView(height: 56,
                                            stroke: TokenPaneStyle.uncachedColor,
                                            fill: TokenPaneStyle.uncachedColor)

    /// 用量屏：天趋势卡（整屏独占，走势给足 88pt）
    let trendCard = TokenCardRow(height: 144, background: TokenPaneStyle.cardFill)
    let trendTitle = MenuPanelLabel.text("天趋势 · 固定 14 天", font: TokenPaneStyle.cardHeadTitleFont,
                                         color: TokenPaneStyle.secondaryText)
    let trendMeta = MenuPanelLabel.text("", font: TokenPaneStyle.metaNumberFont,
                                        color: TokenPaneStyle.tertiaryText)
    let trendAction = TokenTextButton(title: "切：分线")
    let trendSpark = TokenSparkView(height: TokenPaneStyle.usageTrendHeight,
                                    stroke: TokenPaneStyle.uncachedColor,
                                    fill: TokenPaneStyle.uncachedColor)

    /// 用量屏：今日 vs 昨日同期（无对照窗口时整卡隐藏，不编数）
    let compareCard = TokenCardRow(height: 50, background: TokenPaneStyle.cardFill)
    let compareTotal = MenuPanelLabel.text("", font: TokenPaneStyle.metaNumberFont,
                                           color: TokenPaneStyle.tertiaryText)
    let compareDelta = MenuPanelLabel.text("", font: TokenPaneStyle.yoyFont,
                                           color: TokenPaneStyle.warnInk)
    let compareCurrentRow = TokenCompareRowView()
    let comparePreviousRow = TokenCompareRowView()

    /// 缓存屏（大环 + 四行拆分 / 趋势 / 对照 / 统计 + 口径），自带内容栈
    let cacheScreen = TokenCacheScreenView()
    /// 排行屏（维度分段 + 占比条 + Top 8 两行式行 + 计数），自带内容栈
    let rankScreen = TokenRankingScreenView(cardHeight: TokenPaneView.rankingCardHeight)
    /// 四个屏的外框（顺序 = TokenScreen.allCases；渲染按 screen 切显隐）
    ///
    /// 外框高度给死（screenHeight）→ 四屏 pane 高度一致 → 切屏时 popover 不跳高跳低；
    /// 屏内 = 内容滚动区 + 页脚（状态带 / 口径说明），超高内容走屏内滚动。
    var screenFrames: [TokenScreenFrameView] = []

    /// 屏外框高度：520（popover 上限）− 顶 10 − 分页条 28 − 间距 12 − 底 12 − 页头 22 − 间隙 3
    /// − 屏切换条 20 − 屏间距 4 = 409；于是 pane = 458，desiredContentHeight 恰好 520（不再触发外框滚动）
    static let screenHeight: CGFloat = 409

    /// 排行卡高度 = 外框 − 页脚状态带 − 间距：卡片撑到页脚上方，可见行均分这块高度
    static let rankingCardHeight: CGFloat = screenHeight - PaneCardStyle.stateBandHeight - 4

    /// 二级页容器（覆盖在主面板之上，同一 Pane 内切换）
    let detailPane = TokenDetailPaneView()

    // MARK: - 状态页

    let dataStack = NSStackView()
    /// 页头下方的内容起点（buildHeader 里赋值为页头底边）
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
        // 二级页打开时只留返回入口：返回空数组会让键盘用户进得去出不来
        guard detailKind == nil else { return detailPane.focusableRows }
        // 页头三组行（刷新 / 范围 / 屏切换条）永远在前且数量固定：
        // 切屏只改变其后的行，焦点下标不会指向别的控件
        var rows: [MenuPanelRow] = [refreshRow]
        rows.append(contentsOf: rangeControl.focusableRows)
        rows.append(contentsOf: screenControl.focusableRows)
        if !dataStack.isHidden {
            switch screen {
            case .overview:
                rows.append(contentsOf: familyCards)
                rows.append(cacheHitStrip)
                rows.append(overviewTrendCard)
            case .usage:
                if range == .today { rows.append(contentsOf: daySegment.focusableRows) }
                rows.append(hourCard)
                rows.append(trendCard)
            case .cache:
                rows.append(contentsOf: cacheScreen.focusableRows)
            case .ranking:
                rows.append(contentsOf: rankScreen.focusableRows)
            }
        }
        if !emptyView.isHidden { rows.append(emptyView.retryRow) }
        return rows
    }

    // MARK: - 数据更新

    func update(_ snapshot: HarnessUsageSnapshot) {
        self.snapshot = snapshot
        applyStateMachine()
    }

    // MARK: - 屏切换

    /// 切换屏：先切显隐再渲染，渲染末尾统一通知面板按新屏重算高度（各屏不做等高等）
    func selectScreen(_ value: TokenScreen) {
        guard screen != value else { return }
        screen = value
        screenControl.select(value.rawValue, notify: false)
        applyScreenVisibility()
        // 新屏从顶部开始看：沿用上一屏的滚动位置会让人以为内容没换
        screenFrames[safe: value.rawValue]?.scrollToTop()
        guard lastModel != nil else {
            onContentChanged?()
            return
        }
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
        overviewTrendCard.onClick = { [weak self] in self?.openDetail(.trend) }
        screenControl.onSelect = { [weak self] index in
            guard let self, let value = TokenScreen(rawValue: index) else { return }
            self.selectScreen(value)
        }
        // 排行屏的维度分段与屏切换走同一条 render 路径（不各走一套刷新）
        rankScreen.onDimensionChange = { [weak self] in self?.render() }
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

    /// 快照自证专用（仅 DEBUG）：切到指定屏（4 屏 × 浅/深取证）
    func selectScreenForSnapshot(_ screen: TokenScreen) {
        selectScreen(screen)
    }
#endif
}
