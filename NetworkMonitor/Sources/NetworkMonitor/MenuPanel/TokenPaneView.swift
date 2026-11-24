import AppKit
import NetworkMonitorCore
import NetworkMonitorDesign
import NetworkMonitorUI

// MARK: - Token 页

/// Token 消耗页 —— 菜单面板第 5 个 tab
///
/// 数据由 HarnessUsageSnapshot 注入（update），本视图不直接访问数据库或索引服务。
/// 版式（v3 两屏）：页头（来源 + 会话数 + 范围 + 刷新）→ 屏切换条（总览 / 分布）→ 当前屏内容。
/// 收敛依据：改前 4 屏每屏只用掉约 300/409pt，下方常年空白、看全数据要切三次屏。
/// 缓存命中从独立屏降级为二级页（TokenDetailKind.cache），主面板只留一条可点的命中率条。
/// 区块归属由 TokenScreen 契约给出（NetworkMonitorUI，纯逻辑可断言）；两个屏高度一致，
/// 切屏走 onContentChanged 让面板重算 popover 尺寸。
///
/// 成员分布：页头装配与来源同步在 TokenHeaderSection.swift，状态机与二级页在 +State.swift，
/// 布局在 +Layout.swift，渲染在 +Render.swift，屏内容在 TokenScreenContent*.swift，
/// 二级页在 TokenDetailPages*.swift。
final class TokenPaneView: MenuPanelPaneView {

    // MARK: - 回调

    var onRefresh: (() -> Void)?
    var onContentChanged: (() -> Void)?
    /// 打开统一设置窗口（不可用态的动作行用；参数即要落到的分类）
    var onOpenSettings: ((SettingsSection?) -> Void)?
    /// 索引服务（页头「一键重扫」用；由面板装配时注入，nil 时空转）
    var harness: (any HarnessUsageServicing)?
    /// 临时提示（重扫过程 / 回执）：状态机每次重渲都会把它贴回索引标签，8 秒后自动清掉
    var durableNote: (text: String, isWarning: Bool)?
    /// 临时提示的自动清除任务（新提示会取消旧任务，避免串台）
    var noteExpiry: Task<Void, Never>?

    // MARK: - 交互状态

    // 下面五个交互状态由 wireActions（TokenPaneView+Interaction.swift）写入：
    // 跨文件访问故去掉 private(set)，写入路径只有那一个扩展与 DEBUG 取证入口。
    /// 当前来源（nil = 全部 / 跨源合计）—— 页头切换器写入，两屏与二级页共用同一口径
    var source: TokenSourceID?
    var range: TokenRange = .today
    var hourScope: TokenHourScope = .today
    var hourView: TokenHourView = .stack
    var metric: TokenChartMetric = .total
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
    /// 当前来源收窄后的快照 —— 状态机 / 两屏 / 二级页的唯一数据入口
    ///
    /// 收窄是全同形的（日/时桶、项目/模型、可用性诊断都在内），所以「跟随来源」不必
    /// 在各区块里逐处判断，只要换这一个入口。
    var scopedSnapshot: HarnessUsageSnapshot? {
        snapshot.map { TokenSourceScope.narrow($0, to: source) }
    }
    /// 偏好存储（来源选择 / 自动监控开关都走它，禁止 UserDefaults.standard）
    var storage: any KeyValueStorage { AppContext.shared.storage }
    var lastModel: TokenPaneModel?

    // MARK: - 页头

    /// 范围分段（窗口边界按 Asia/Shanghai 切分，页头时区提示里写明）
    let rangeControl = TokenSegmentedControl(titles: TokenRange.allCases.map { $0.title })
    /// 屏切换条（页头下一行，两段等宽）
    let screenControl = TokenSegmentedControl(titles: TokenScreen.titles, expands: true)
    let refreshRow = TokenIconButtonRow(symbolName: "arrow.clockwise")
    /// 索引进度 / 失败原因 / 重扫回执 —— 显示在**页头 meta 位**（会话数那一格）
    ///
    /// 改前它是一条独立标签、排在屏切换条上方：索引期间多出一行（约 15pt），
    /// 两屏内容预算 385pt 已经填满，一出现就顶出外框滚动条、把页脚状态带挤没。
    /// 页头 meta 位本来就写「2218 会话」这类口径文字，索引中改写成「索引中 2/6 · 500 行」
    /// 语义也顺（都是「当前看到的数据是什么状态」），且零高度成本。
    var indexNote: String?
    /// 索引提示是否为告警语气（失败 / 重扫未执行）
    var indexNoteIsWarning = false
    /// 页头行（来源切换器 → 会话数 → 范围分段 → 刷新），右侧口径文字与时区提示都挂在这条上
    ///
    /// 页名位由来源切换器替换（buildHeader 调 setTitleControl）；骨架本身没动，页头仍是 22pt。
    let headerView = PaneHeaderRowView(title: "")
    /// 来源切换器（占页名位）——「全部 ▾」；菜单里只列已启用且有数据的来源
    let sourceSelector = TokenSourceSelectorView()

    // MARK: - 分区

    /// 总览屏 Hero（当前范围三项合计 + 较昨日 + 实时）
    let heroView = TokenHeroView()
    lazy var familyCards = TokenMetric.allCases.map { metric in
        TokenFamilyCardView(metric: metric, onClick: {})
    }
    /// 四族卡矩阵容器（2×2）
    let familyGrid = NSStackView()
    /// 屏页脚状态带：两屏各一个实例，都用同一份 model.stateBand 更新
    ///
    /// 用的是五页共用的 `PaneStateBandView`（底 / 高度 / 内边距 / 圆角 / 键值字号走
    /// `PaneBandChrome`）；Token 页此前那份 `TokenStateBandView` 已删除，只保留语气色映射。
    let overviewBand = PaneStateBandView()
    let distroBand = PaneStateBandView()
    /// 两个状态带实例（渲染时统一刷新）
    var stateBands: [PaneStateBandView] { [overviewBand, distroBand] }

    /// 总览屏：主图卡（24 桶 / 按天 N 桶，柱高 96pt；每根柱可点进单桶页）
    ///
    /// 高度 = Hero 46 + 四族 122 + 缓存条 42 + 3×间距 12 + 主图 163 = 385pt（= 409 − 状态带 20 − 间距 4），
    /// 恰好填满屏内容预算、不触发屏内滚动。
    let hourCard = TokenCardRow(height: 163, background: TokenPaneStyle.cardFill)
    let hourTitle = MenuPanelLabel.text("", font: TokenPaneStyle.cardHeadTitleFont,
                                        color: TokenPaneStyle.secondaryText)
    let hourMeta = MenuPanelLabel.text("", font: TokenPaneStyle.metaNumberFont,
                                       color: TokenPaneStyle.tertiaryText)
    let hourAction = TokenTextButton(title: "切：请求数")
    let daySegment = TokenSegmentedControl(titles: TokenHourScope.allCases.map { $0.title })
    /// 主图形态切换（堆叠 / 对比）——收成单按钮，省掉第二个分段控件的宽度
    let viewAction = TokenTextButton(title: "切：对比")
    /// 进「天趋势」二级页（原先靠用量屏的趋势卡承担，两屏收敛后改由主图卡头承担）
    let trendAction = TokenTextButton(title: "14 天 ›")
    let hourBars = TokenBarsView()
    let hourAxis = TokenAxisView()
    let hourLegend = TokenLegendRowView()

    /// 总览屏：缓存命中紧凑条（小环 + 命中率大字 + 三个值，数据取 model.cachePage）
    ///
    /// 整条可点 → 打开缓存命中二级页（环 / 命中率走势 / 本周期对照 / 样本统计 + 口径说明）。
    lazy var cacheHitStrip = TokenCacheHitStripView(onClick: { [weak self] in
        self?.openDetail(.cache)
    })

    /// 分布屏（维度分段 + 占比条 + Top 8 两行式行 + 汇总），自带内容栈
    ///
    /// 卡高 = 屏内容预算 385 − 对照卡 50 − 间距 4 = 331pt。
    let rankScreen = TokenRankingScreenView(cardHeight: TokenPaneView.rankingCardHeight)
    /// 分布屏：今日 vs 昨日同期（无对照窗口时整卡隐藏，不编数）
    let compareCard = TokenCardRow(height: 50, background: TokenPaneStyle.cardFill)
    let compareTotal = MenuPanelLabel.text("", font: TokenPaneStyle.metaNumberFont,
                                           color: TokenPaneStyle.tertiaryText)
    let compareDelta = MenuPanelLabel.text("", font: TokenPaneStyle.yoyFont,
                                           color: TokenPaneStyle.warnInk)
    let compareCurrentRow = TokenCompareRowView()
    let comparePreviousRow = TokenCompareRowView()

    /// 两个屏的外框（顺序 = TokenScreen.allCases；渲染按 screen 切显隐）
    ///
    /// 外框高度给死（screenHeight）→ 两屏 pane 高度一致 → 切屏时 popover 不跳高跳低；
    /// 屏内 = 内容滚动区 + 页脚状态带，超高内容走屏内滚动。
    var screenFrames: [TokenScreenFrameView] = []

    /// 屏外框高度：520（popover 上限）− 顶 10 − 分页条 28 − 间距 12 − 底 12 − 页头 22 − 间隙 3
    /// − 屏切换条 20 − 屏间距 4 = 409；于是 pane = 458，desiredContentHeight 恰好 520（不再触发外框滚动）
    static let screenHeight: CGFloat = 409

    /// 屏内容预算 = 外框 − 页脚状态带 − 间距（两屏都用到最后一 pt，不留尾巴）
    static var screenContentHeight: CGFloat { screenHeight - PaneCardStyle.stateBandHeight - 4 }

    /// 分布屏卡片高度 = 内容预算 − 对照卡 − 间距
    static var rankingCardHeight: CGFloat { screenContentHeight - 50 - PaneCardStyle.cardSpacing }

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
        // 来源选择是持久化的：面板每次重开接着上次的来源看
        source = TokenSourcePreferences.selectedSource(AppContext.shared.storage)
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
        var rows: [MenuPanelRow] = [sourceSelector, refreshRow]
        rows.append(contentsOf: rangeControl.focusableRows)
        rows.append(contentsOf: screenControl.focusableRows)
        if !dataStack.isHidden {
            switch screen {
            case .overview:
                rows.append(contentsOf: familyCards)
                rows.append(cacheHitStrip)
                if range == .today { rows.append(contentsOf: daySegment.focusableRows) }
                rows.append(hourCard)
            case .distro:
                rows.append(contentsOf: rankScreen.focusableRows)
            }
        }
        if !emptyView.isHidden { rows.append(emptyView.retryRow) }
        // 不可用态的「去设置」也要能键盘到达，否则键盘用户看到失败原因却没有任何出口
        if !unavailableView.isHidden { rows.append(unavailableView.actionRow) }
        return rows
    }

    // MARK: - 数据更新

    func update(_ snapshot: HarnessUsageSnapshot) {
        self.snapshot = snapshot
        applyStateMachine()
    }

    // MARK: - 屏切换

    /// 切换屏：先切显隐再渲染，渲染末尾统一通知面板按新屏重算高度（两屏不做等高等）
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

#if DEBUG
    /// 快照自证专用（仅 DEBUG）：切换范围 / 小时归属 / 主图形态（堆叠·对比）
    ///
    /// 天趋势形态随「天趋势」独立屏一起下线，取证入口不再接收它：
    /// 收了也没有第二处读它，只会让每个调用点多写一个恒定实参。
    func applyStateForSnapshot(range: TokenRange, hourScope: TokenHourScope,
                               hourView: TokenHourView? = nil, metric: TokenChartMetric? = nil) {
        self.range = range
        self.hourScope = hourScope
        if let hourView { self.hourView = hourView }
        if let metric { self.metric = metric }
        if snapshot != nil { render() }
    }

    /// 快照自证专用（仅 DEBUG）：打开指定二级页（取证用）
    func openDetailForSnapshot(_ kind: TokenDetailKind, selection: TokenBucketSelection? = nil) {
        openDetail(kind, selection: selection)
    }

    /// 快照自证专用（仅 DEBUG）：切到指定屏（2 屏 × 浅/深取证）
    func selectScreenForSnapshot(_ screen: TokenScreen) {
        selectScreen(screen)
    }
#endif
}
