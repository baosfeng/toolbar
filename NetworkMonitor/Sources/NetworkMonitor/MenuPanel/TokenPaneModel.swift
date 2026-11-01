import Foundation
import NetworkMonitorCore

// MARK: - Token 页展示模型（定稿原型 final-定稿.html 口径）

/// 统计范围
enum TokenRange: Int, CaseIterable {
    case today
    case d7
    case d30

    var title: String {
        switch self {
        case .today: return "今日"
        case .d7: return "近 7 天"
        case .d30: return "近 30 天"
        }
    }

    /// 窗口天数
    var days: Int {
        switch self {
        case .today: return 1
        case .d7: return 7
        case .d30: return 30
        }
    }

    /// 主图桶数：今日 24 小时桶，其余按天
    var bucketCount: Int {
        self == .today ? 24 : days
    }
}

/// 小时图看哪一天（真换数据，不是换标签）
enum TokenHourScope: Int, CaseIterable {
    case today
    case yesterday

    var title: String { self == .today ? "今日" : "昨日" }
    var otherTitle: String { self == .today ? "昨日" : "今日" }
}

/// 主图形态：堆叠三段 / 折线对比
enum TokenHourView: Int, CaseIterable {
    case stack
    case compare

    var title: String { self == .stack ? "堆叠" : "对比" }
}

/// 主图指标：三段总量 / 请求数
enum TokenChartMetric: Int, CaseIterable {
    case total
    case request

    var title: String { self == .total ? "总量" : "请求数" }
}

/// 天趋势形态：面积 / 分线
enum TokenTrendMode: Int, CaseIterable {
    case stack
    case line

    var title: String { self == .stack ? "面积" : "分线" }
}

/// 四个指标族
enum TokenMetric: Int, CaseIterable {
    case uncached
    case output
    case cache
    case request

    var title: String {
        switch self {
        case .uncached: return "未缓存输入"
        case .output: return "输出"
        case .cache: return "缓存读"
        case .request: return "请求数"
        }
    }

    /// 是否属于 tok 三段（请求数单独处理）
    var isToken: Bool { self != .request }
}

/// 单桶（小时 / 天）用量
struct TokenBucket {
    let label: String
    let uncached: Int
    let output: Int
    let cache: Int
    let request: Int

    static let empty = TokenBucket(label: "", uncached: 0, output: 0, cache: 0, request: 0)

    /// 三段相加 = 该桶总 tok（请求数与 tok 不同源，不进这个合计）
    var total: Int { uncached + output + cache }

    init(label: String, uncached: Int, output: Int, cache: Int, request: Int) {
        self.label = label
        self.uncached = uncached
        self.output = output
        self.cache = cache
        self.request = request
    }

    init(label: String, usage: HarnessTokenUsage?) {
        self.label = label
        uncached = usage?.uncachedInput ?? 0
        output = usage?.output ?? 0
        cache = usage?.cacheRead ?? 0
        request = usage?.requestCount ?? 0
    }
}

/// 分族卡（2×2 首屏矩阵的一格）
struct TokenFamilyCard {
    let metric: TokenMetric
    let title: String
    /// 数值主体（已缩写，如 1.30）
    let value: String
    /// 单位（如 M tok / 次）
    let unit: String
    /// 辅助行（同比与占比合并成一行，如「↑ 35% · 占 2.3%」）
    let aux: String
    /// 辅助行是否为上行（决定墨色）
    let deltaUp: Bool
    /// 辅助行是否为同比（false = 无同比时的日均文案，用三级色）
    let hasDelta: Bool
    /// sparkline 序列（请求数卡画迷你柱）
    let series: [Double]
}

/// 首屏 Hero（今日 / 当前范围的三项合计）
struct TokenHero {
    /// 「今日总消耗」/「近 7 天总消耗」
    let title: String
    /// 数值主体（已缩写，如 17.67）
    let value: String
    /// 单位（如 M tok）
    let unit: String
    /// 「较昨日 ↓ 23.3%」
    let delta: String
    let deltaUp: Bool
    /// 有无同比（昨日为 0 时没有，用三级色不编数）
    let hasDelta: Bool
    /// 「实时 17:05」
    let clock: String
}

/// 分布行（项目 / 模型）
struct TokenDistroRow {
    let rank: Int
    let name: String
    /// provider 前缀（模型行用，其余为空）
    let provider: String
    /// 第二行说明（模型详情的 provider + 占比）
    let sub: String
    let amount: String
    let share: Double
    let colorIndex: Int
}

/// 底状态带的一格
struct TokenStateItem {
    enum Tone {
        case plain
        case accent
        case cache
        case request
    }

    let title: String
    let value: String
    let tone: Tone
}

/// Token 页展示模型 —— 由快照 + 交互状态派生出的只读视图数据
///
/// 口径（与定稿原型逐条对齐）：
/// - 四族卡 / 小时图 / 天趋势 / 缓存卡跟随范围；
/// - 项目与模型**只有累计口径**，切范围不跟着变；
/// - 按小时桶只有今日与昨日，历史日只给天粒度。
struct TokenPaneModel {

    let range: TokenRange
    let hostLabel: String
    let stamp: String
    /// 首屏 Hero（当前范围三项合计 + 较昨日 + 实时）
    let hero: TokenHero

    let cards: [TokenFamilyCard]

    /// 主图桶（今日 24 桶 / 按天 N 桶）
    let buckets: [TokenBucket]
    /// 对照桶（同时段昨日 / 上一周期）
    let prevBuckets: [TokenBucket]
    let bucketTitle: String
    let bucketMeta: String
    /// 图例（标题 + 数值）
    let bucketLegend: [(title: String, value: String)]
    /// 累计虚线基准（无量纲，按当前序列累加）
    let cumulative: [Double]
    let cumulativeText: String

    let trendBuckets: [TokenBucket]
    let trendTitle: String
    let trendMeta: String

    let hitText: String
    let hitMeta: String
    let cacheReadText: String
    let uncachedText: String
    let hitSeries: [Double]
    /// 当前口径命中率（0…1，环形图用）
    let hitRateFraction: Double
    let hitBucketText: String

    let projects: [TokenDistroRow]
    let models: [TokenDistroRow]
    let projectMeta: String
    let modelMeta: String
    let projectCount: Int
    let modelCount: Int

    /// 今日 vs 昨日同期（按天范围且取不到上一周期时为 nil，整卡隐藏，不编数）
    let compare: TokenCompare?
    let stateBand: [TokenStateItem]
    let indexedSessions: Int
    let hasData: Bool

    /// 今日 vs 昨日对比条
    struct TokenCompare {
        let currentLabel: String
        let previousLabel: String
        let currentText: String
        let previousText: String
        let currentFraction: Double
        let previousFraction: Double
        let deltaText: String
        let deltaUp: Bool
    }

    /// 由快照与交互状态派生展示模型
    static func make(snapshot: HarnessUsageSnapshot,
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
