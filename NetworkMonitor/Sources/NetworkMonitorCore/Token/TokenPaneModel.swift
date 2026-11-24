import Foundation

/// Token 页展示模型 —— 由快照 + 交互状态派生出的只读视图数据
///
/// 口径（与定稿原型逐条对齐）：
/// - 四族卡 / 小时图 / 天趋势 / 缓存卡跟随范围；
/// - 项目与模型**跟随范围**（今日 / 近 7 天 / 近 30 天各一份聚合），与 Hero 同口径；
///   用户反馈「上面的数据和下面的数据对不上（340M vs 7.13B）」就是两套口径造成的；
/// - 按小时桶只有今日与昨日，历史日只给天粒度。
package struct TokenPaneModel {

    package let range: TokenRange
    /// 当前来源（nil = 全部 / 跨源合计）；数据口径由它决定
    package let source: TokenSourceID?
    /// 页头可选的来源（已启用且有数据）——页名文案由它与 source 一起决定
    package let availableSources: [TokenSourceID]
    /// 页名实际显示的来源：只有一个「有数据的来源」时直接显示它
    package var displaySource: TokenSourceID? {
        TokenSourceScope.displaySource(selected: source, dataSources: availableSources)
    }
    /// 页头页名文案（来源显示名；两个以上可用来源且看合计时为「全部」）
    package var sourceLabel: String { displaySource?.displayName ?? "全部" }
    package let hostLabel: String
    package let stamp: String
    /// 首屏 Hero（当前范围三项合计 + 较昨日 + 实时）
    package let hero: TokenHero

    package let cards: [TokenFamilyCard]

    /// 主图桶（今日 24 桶 / 按天 N 桶）
    package let buckets: [TokenBucket]
    /// 对照桶（同时段昨日 / 上一周期）
    package let prevBuckets: [TokenBucket]
    package let bucketTitle: String
    package let bucketMeta: String
    /// 图例（标题 + 数值）
    package let bucketLegend: [(title: String, value: String)]
    /// 累计虚线基准（无量纲，按当前序列累加）
    package let cumulative: [Double]

    package let cacheReadText: String
    package let uncachedText: String

    package let projects: [TokenDistroRow]
    package let models: [TokenDistroRow]
    package let projectMeta: String
    package let modelMeta: String
    package let projectCount: Int
    package let modelCount: Int
    /// 当前范围的项目 / 模型合计（与占比分母同源，排行屏汇总块用）
    package let projectTotals: TokenDistroTotals
    package let modelTotals: TokenDistroTotals
    /// 「按工具」的行与合计（= 按来源；只在页头为「全部」时进排行屏）
    package let tools: [TokenDistroRow]
    package let toolTotals: TokenDistroTotals

    /// 「按项目 / 按模型」二级页的范围口径文案（Core 派生，视图只透传）
    package let distroCopy: TokenDistroCopy

    /// 缓存命中二级页的全套数值与文案（跟随当前范围，Core 派生，视图只透传）
    ///
    /// 与 distroCopy 同理：这页曾写死「主数值今日 / 走势与均值 30 天 / 逐桶今日 24 桶」，
    /// 用户把主面板切到近 7 天后页面仍是混合口径。数字与文案必须在 Core 里派生，
    /// TestRunner 才能断言「换范围真的换了数据」。
    package let cachePage: TokenCachePage

    /// 今日 vs 昨日同期（按天范围且取不到上一周期时为 nil，整卡隐藏，不编数）
    package let compare: TokenCompare?
    package let stateBand: [TokenStateItem]
    package let indexedSessions: Int
    package let hasData: Bool

    /// 今日 vs 昨日对比条
    package struct TokenCompare {
        package let currentLabel: String
        package let previousLabel: String
        package let currentText: String
        package let previousText: String
        package let currentFraction: Double
        package let previousFraction: Double
        package let deltaText: String
        package let deltaUp: Bool
    }

    /// 由快照与交互状态派生展示模型
    package static func make(snapshot: HarnessUsageSnapshot,
                     range: TokenRange,
                     source: TokenSourceID? = nil,
                     availableSources: [TokenSourceID]? = nil,
                     hourScope: TokenHourScope,
                     hourView: TokenHourView,
                     metric: TokenChartMetric,
                     now: Date = Date()) -> TokenPaneModel {
        let today = TokenDerive.todayBuckets(snapshot)
        let yesterday = TokenDerive.yesterdayBuckets(snapshot)
        let windowBuckets = range == .today ? (hourScope == .today ? today : yesterday) : TokenDerive.dailyBuckets(snapshot, days: range.days)
        let prevWindow = range == .today ? (hourScope == .today ? yesterday : today) : TokenDerive.previousDailyBuckets(snapshot, days: range.days)
        let windowTotal = TokenDerive.sum(windowBuckets)
        let windowPrevTotal = TokenDerive.sum(prevWindow)

        let todayTotal = TokenDerive.sum(today)
        let yesterdayTotal = TokenDerive.sum(yesterday)
        let currentTotal = range == .today ? todayTotal : TokenDerive.sum(TokenDerive.dailyBuckets(snapshot, days: range.days))
        let previousTotal = range == .today ? yesterdayTotal : TokenDerive.sum(TokenDerive.previousDailyBuckets(snapshot, days: range.days))

        // 项目 / 模型跟随范围：与 Hero、四族卡取同一个窗口
        let projectRows = TokenDerive.projectRows(snapshot, window: range.window)
        let modelRows = TokenDerive.modelRows(snapshot, window: range.window)
        // 二级页文案与主面板同源派生，避免「上面跟随范围、下面写累计口径」再次分叉
        let distroCopy = TokenDerive.distroCopy(range: range)
        // 有数据的来源：调用方（页头菜单）给了就用它，否则按快照的 bySource 自己推
        let dataSources = availableSources ?? TokenSourceScope.dataSources(in: snapshot)
        // 缓存命中页与主面板缓存卡共用同一份派生：卡片大数字 / 图例桶数 / 环形比例
        // 全部取自 cachePage，视图层不再各算一遍（改前主面板说「昨日 97.1%」而圆环画的是今日，
        // 就是两套算式各走各的留下的坑）。
        // 来源数用这里已经算好的 dataSources：脚注「跨 N 个来源合并」的 N 与页头同一份判据，
        // 不另读偏好，也不在 Core 里再推一次。
        let cachePage = TokenDerive.cachePage(snapshot, range: range, sourceCount: dataSources.count)
        // 页名：显式选了来源就写它；只有一个有数据的来源时也写它
        let pageName = TokenSourceScope.displaySource(selected: source, dataSources: dataSources)?
            .displayName ?? "全部"

        return TokenPaneModel(
            range: range,
            source: source,
            availableSources: dataSources,
            // 页名（来源）与口径（会话数）同源派生：页头左侧是来源切换器，
            // 右侧只留会话数（TokenPaneView+Layout 的 headerMeta 负责去前缀）。
            // 只有一个可用来源时页名直接写它，避免「全部 · 2147 会话」而实际只有一个源
            hostLabel: pageName + " · \(snapshot.indexedSessions) 会话",
            stamp: TokenFormatting.clock(now),
            hero: TokenDerive.hero(range: range, current: currentTotal, previous: previousTotal,
                                   clock: TokenFormatting.clock(now)),
            cards: TokenDerive.familyCards(range: range,
                                          buckets: windowBuckets,
                                          prevBuckets: prevWindow,
                                          total: currentTotal,
                                          prevTotal: previousTotal),
            buckets: windowBuckets,
            prevBuckets: prevWindow,
            bucketTitle: TokenDerive.bucketTitle(range: range, hourScope: hourScope, hourView: hourView),
            bucketMeta: TokenDerive.bucketMeta(range: range, buckets: windowBuckets, prev: prevWindow,
                                               hourScope: hourScope, hourView: hourView, metric: metric),
            bucketLegend: TokenDerive.bucketLegend(range: range, total: windowTotal, prev: windowPrevTotal,
                                                   hourScope: hourScope, hourView: hourView, metric: metric),
            cumulative: TokenDerive.cumulative(windowBuckets, metric: metric),
            cacheReadText: TokenFormatting.tokens(currentTotal.cache),
            uncachedText: TokenFormatting.tokens(currentTotal.uncached),
            projects: projectRows,
            models: modelRows,
            projectMeta: "\(distroCopy.rangeTitle) \(projectRows.count) 个",
            modelMeta: "\(distroCopy.rangeTitle) \(modelRows.count) 个",
            projectCount: projectRows.count,
            modelCount: modelRows.count,
            projectTotals: TokenDistroTotals(usage: snapshot.windowProjectTotals[range.window] ?? .zero),
            modelTotals: TokenDistroTotals(usage: snapshot.windowModelTotals[range.window] ?? .zero),
            tools: TokenToolRanking.rows(snapshot, range: range),
            toolTotals: TokenToolRanking.totals(snapshot, range: range),
            distroCopy: distroCopy,
            cachePage: cachePage,
            compare: TokenDerive.compare(snapshot, current: currentTotal, previous: previousTotal, range: range),
            stateBand: TokenDerive.stateBand(snapshot, range: range, buckets: windowBuckets,
                                             previous: previousTotal, current: currentTotal),
            indexedSessions: snapshot.indexedSessions,
            hasData: !TokenComparison.isEmpty(snapshot))
    }
}