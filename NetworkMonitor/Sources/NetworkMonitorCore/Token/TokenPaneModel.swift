import Foundation

/// Token 页展示模型 —— 由快照 + 交互状态派生出的只读视图数据
///
/// 口径（与定稿原型逐条对齐）：
/// - 四族卡 / 小时图 / 天趋势 / 缓存卡跟随范围；
/// - 项目与模型**只有累计口径**，切范围不跟着变；
/// - 按小时桶只有今日与昨日，历史日只给天粒度。
package struct TokenPaneModel {

    package let range: TokenRange
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
    package let cumulativeText: String

    package let trendBuckets: [TokenBucket]
    package let trendTitle: String
    package let trendMeta: String

    package let hitText: String
    package let hitMeta: String
    package let cacheReadText: String
    package let uncachedText: String
    package let hitSeries: [Double]
    /// 当前口径命中率（0…1，环形图用）
    package let hitRateFraction: Double
    package let hitBucketText: String

    package let projects: [TokenDistroRow]
    package let models: [TokenDistroRow]
    package let projectMeta: String
    package let modelMeta: String
    package let projectCount: Int
    package let modelCount: Int

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
                     hourScope: TokenHourScope,
                     hourView: TokenHourView,
                     metric: TokenChartMetric,
                     trendMode: TokenTrendMode,
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

        return TokenPaneModel(
            range: range,
            hostLabel: "DSH · \(snapshot.indexedSessions) 会话",
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
            cumulativeText: TokenFormatting.tokens(TokenDerive.metricTotal(windowBuckets, metric: metric)),
            trendBuckets: TokenDerive.dailyBuckets(snapshot, days: 14),
            trendTitle: "天趋势 · 固定 14 天",
            trendMeta: TokenDerive.trendMeta(snapshot),
            hitText: TokenFormatting.decimal(TokenDerive.hitRate(currentTotal) * 100),
            hitMeta: "\(range == .today ? hourScope.title : range.title) "
                + TokenFormatting.decimal(TokenDerive.hitRate(currentTotal) * 100) + "%",
            cacheReadText: TokenFormatting.tokens(currentTotal.cache),
            uncachedText: TokenFormatting.tokens(currentTotal.uncached),
            hitSeries: windowBuckets.map { TokenDerive.hitRate($0) * 100 },
            hitRateFraction: TokenDerive.hitRate(currentTotal),
            hitBucketText: range == .today ? "24 桶" : "\(range.days) 天",
            projects: TokenDerive.projectRows(snapshot),
            models: TokenDerive.modelRows(snapshot),
            projectMeta: "累计 \(snapshot.projects.count) 个",
            modelMeta: "累计 \(snapshot.models.count) 个",
            projectCount: snapshot.projects.count,
            modelCount: snapshot.models.count,
            compare: TokenDerive.compare(snapshot, current: currentTotal, previous: previousTotal, range: range),
            stateBand: TokenDerive.stateBand(snapshot, range: range, buckets: windowBuckets,
                                             previous: previousTotal, current: currentTotal),
            indexedSessions: snapshot.indexedSessions,
            hasData: !TokenComparison.isEmpty(snapshot))
    }
}
