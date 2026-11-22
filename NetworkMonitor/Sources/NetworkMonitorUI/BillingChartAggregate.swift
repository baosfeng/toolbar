import Foundation
import NetworkMonitorCore

// MARK: - 额度页图表口径（纯逻辑，可单测）

/// 图表口径 —— 跨 provider 的时间桶加总、Top N 模型排序、空数据判定
///
/// 与总表口径（BillingAggregate）分开成两个概念：一张表讲「现在还剩多少」，
/// 一张图讲「这段时间用了多少」，判据、入参、失败模式都不一样。
/// 两者都留在 UI 库，TestRunner 才能直接断言（App 是可执行 target，测不了）。
public enum BillingChartAggregate {

    /// 图表指标 —— 请求数优先；整组都没有请求数时退回花费
    public enum Metric: Equatable {
        case requests
        case spend
    }

    /// 一根柱 / 一个折线点
    public struct ChartPoint: Equatable {
        /// 轴标签（24h 用两位小时，7d / 30d 用两位日）
        public let label: String
        /// 绘图值（请求数或金额）
        public let value: Double
        /// 是否最新一格（最后一根用强调色）
        public let isCurrent: Bool

        public init(label: String, value: Double, isCurrent: Bool) {
            self.label = label
            self.value = value
            self.isCurrent = isCurrent
        }
    }

    /// 一张跨 provider 汇总图表的全部数据
    public struct ChartSeries: Equatable {
        public let metric: Metric
        public let points: [ChartPoint]
        /// 合计（请求数或金额）
        public let total: Double
        /// 单格峰值
        public let peak: Double

        public init(metric: Metric, points: [ChartPoint], total: Double, peak: Double) {
            self.metric = metric
            self.points = points
            self.total = total
            self.peak = peak
        }

        /// 没有任何可画的值（空数据 / 全零）
        public var isEmpty: Bool { points.isEmpty || peak <= 0 }
    }

    /// 目标粒度 —— 24h 按小时、7d / 30d 按天
    ///
    /// 不跟 provider 自己的 granularity 走：同一张图里混着「一家给小时桶、
    /// 另一家给天桶」时，只有按目标粒度归一才能对齐同一根柱。
    public static func granularity(for range: BillingRange) -> BillingGranularity {
        range == .last24Hours ? .hour : .day
    }

    /// 柱数上限 —— 24h 8 根、7d 7 根、30d 10 根（与原型实测一致）
    public static func maxBuckets(for range: BillingRange) -> Int {
        switch range {
        case .last24Hours: return 8
        case .last7Days: return 7
        case .last30Days: return 10
        }
    }

    /// 跨 provider 合并成一张图表
    ///
    /// 规则（逐条可测）：
    /// 1. 只吃 usage.range == range 的用量 —— 切了范围但还没拉回来的那家不参与，
    ///    不拿旧范围的数据冒充新范围（否则切到 30d 会瞬间画出一条错的趋势）；
    /// 2. 同一时间桶跨 provider 相加（先按目标粒度归一起点，再按时刻建键）；
    /// 3. 超过上限时等距合并相邻桶（保留时间顺序与总量），不丢数据；
    /// 4. 最后一根标记 isCurrent；一条数据都没有时返回空序列（视图画空态）。
    ///
    /// - Parameters:
    ///   - usages: 各 provider 当前的用量（调用方已剔除 nil）
    ///   - range: 页级范围分段当前选中的范围
    ///   - bucketLimit: 柱数上限（nil = 按范围取默认档）
    public static func chart(usages: [BillingUsage],
                             range: BillingRange,
                             bucketLimit: Int? = nil) -> ChartSeries {
        let matching = usages.filter { $0.range == range && !$0.buckets.isEmpty }
        guard !matching.isEmpty else {
            return ChartSeries(metric: .requests, points: [], total: 0, peak: 0)
        }
        let requestsTotal = matching.reduce(0.0) { sum, usage in
            sum + usage.buckets.reduce(0.0) { $0 + Double(max($1.metrics.requestCount, 0)) }
        }
        // 有请求数就画请求数；整组都没有请求数（纯金额型 provider）才退回花费
        let metric: Metric = requestsTotal > 0 ? .requests : .spend
        let target = granularity(for: range)
        let calendar = Calendar.current

        var order: [Date] = []
        var sums: [Date: Double] = [:]
        for usage in matching {
            for bucket in usage.buckets {
                guard let start = normalizedStart(bucket.start, granularity: target,
                                                  calendar: calendar) else { continue }
                if sums[start] == nil { order.append(start) }
                sums[start, default: 0] += value(of: bucket.metrics, metric: metric)
            }
        }
        let sorted = order.sorted()
        let limit = max(bucketLimit ?? maxBuckets(for: range), 1)
        let merged = merge(sorted.map { ($0, sums[$0] ?? 0) }, limit: limit)
        let points = merged.enumerated().map { index, item in
            ChartPoint(label: axisLabel(item.0, granularity: target, calendar: calendar),
                       value: item.1,
                       isCurrent: index == merged.count - 1)
        }
        return ChartSeries(metric: metric,
                           points: points,
                           total: points.reduce(0) { $0 + $1.value },
                           peak: points.map(\.value).max() ?? 0)
    }

    /// 单桶取值
    static func value(of metrics: BillingMetrics, metric: Metric) -> Double {
        switch metric {
        case .requests: return Double(max(metrics.requestCount, 0))
        case .spend: return max(metrics.usageUSD ?? 0, 0)
        }
    }

    /// 按目标粒度归一桶起点（小时截到整点、天截到零点；本地时区）
    static func normalizedStart(_ date: Date,
                               granularity: BillingGranularity,
                               calendar: Calendar) -> Date? {
        let component: Calendar.Component = granularity == .hour ? .hour : .day
        return calendar.dateInterval(of: component, for: date)?.start
    }

    /// 轴标签：24h 用两位小时（「14」），天粒度用两位日（「16」）
    static func axisLabel(_ date: Date, granularity: BillingGranularity,
                          calendar: Calendar) -> String {
        let component: Calendar.Component = granularity == .hour ? .hour : .day
        return String(format: "%02d", calendar.component(component, from: date))
    }

    /// 超过上限时等距合并（保留顺序、总量不变、末组吃到最新一格）
    static func merge(_ points: [(Date, Double)], limit: Int) -> [(Date, Double)] {
        guard limit > 0, points.count > limit else { return points }
        let size = Double(points.count) / Double(limit)
        var result: [(Date, Double)] = []
        for index in 0..<limit {
            let lower = min(Int((Double(index) * size).rounded(.down)), points.count - 1)
            let rawUpper = index == limit - 1
                ? points.count
                : Int((Double(index + 1) * size).rounded(.down))
            let upper = min(max(rawUpper, lower + 1), points.count)
            let slice = points[lower..<upper]
            guard let first = slice.first else { continue }
            result.append((first.0, slice.reduce(0) { $0 + $1.1 }))
        }
        return result
    }

    /// 图表副标题：请求数按「共 N 次 · 日均 M」，金额按「共 $X · 日均 $Y」
    public static func chartSubtitle(_ series: ChartSeries, range: BillingRange) -> String {
        guard !series.isEmpty else { return "暂无数据" }
        switch series.metric {
        case .requests:
            let total = Int(series.total.rounded())
            guard range != .last24Hours else { return "共 " + formatCount(total) + " 次" }
            return "共 " + formatCount(total) + " 次 · 日均 "
                + formatCount(daily(total, range: range))
        case .spend:
            guard range != .last24Hours else { return "共 " + formatUSD(series.total) }
            return "共 " + formatUSD(series.total) + " · 日均 " + formatUSD(daily(series.total, range: range))
        }
    }

    /// 图表头「短口径」：只给合计（柱图卡标题行放不下「共 N 次 · 日均 M」，
    /// 硬塞会把标题截成「近 7 天…」）。完整口径见 chartSubtitle，进 tooltip。
    public static func chartTotalLabel(_ series: ChartSeries) -> String {
        guard !series.isEmpty else { return "暂无数据" }
        switch series.metric {
        case .requests: return "共 " + formatCount(Int(series.total.rounded())) + " 次"
        case .spend: return "共 " + formatUSD(series.total)
        }
    }

    /// 日均（24h 不折算）
    static func daily(_ total: Double, range: BillingRange) -> Double {
        switch range {
        case .last24Hours: return total
        case .last7Days: return total / 7
        case .last30Days: return total / 30
        }
    }

    /// 日均（整数口径，四舍五入）
    static func daily(_ total: Int, range: BillingRange) -> Int {
        guard range != .last24Hours else { return total }
        let divisor = range == .last7Days ? 7.0 : 30.0
        return Int((Double(total) / divisor).rounded())
    }

    /// 请求数文案（千分位，与表内其它数字同一口径）
    static func formatCount(_ value: Int) -> String {
        GroupedNumberFormatting.integer(max(value, 0))
    }

    // MARK: - 模型 Top N

    /// 模型分布的一行
    public struct ModelShare: Equatable {
        /// 模型名（「其他 N 个模型」也算一行）
        public let name: String
        /// 展示值（「1204 万」/「$0.0132」/「1204 次」）
        public let valueLabel: String
        /// 占比 0…1（分母是全部模型，不是 Top N 之内）
        public let share: Double
        /// 是否是「其他」合并行
        public let isOther: Bool

        public init(name: String, valueLabel: String, share: Double, isOther: Bool) {
            self.name = name
            self.valueLabel = valueLabel
            self.share = share
            self.isOther = isOther
        }
    }

    /// 跨 provider 汇总同一模型（同名累加），按权重取 Top N，余下并成「其他」
    ///
    /// 权重：花费 > token 合计 > 请求数（与改造前单卡内排序同一口径，
    /// 只是把分量从「一家」扩到「跨 provider」）。
    public static func topModels(usages: [BillingUsage], range: BillingRange,
                                 limit: Int = 4) -> [ModelShare] {
        let matching = usages.filter { $0.range == range }
        var order: [String] = []
        var merged: [String: BillingMetrics] = [:]
        for usage in matching {
            for group in usage.groups {
                if merged[group.name] == nil { order.append(group.name) }
                merged[group.name] = add(merged[group.name], group.metrics)
            }
        }
        let entries: [(name: String, metrics: BillingMetrics, weight: Double)] =
            order.compactMap { name in
                guard let metrics = merged[name] else { return nil }
                let weight = weight(of: metrics)
                guard weight > 0 else { return nil }
                return (name, metrics, weight)
            }
        guard !entries.isEmpty else { return [] }
        let total = entries.reduce(0.0) { $0 + $1.weight }
        let sorted = entries.sorted { lhs, rhs in
            lhs.weight == rhs.weight ? lhs.name < rhs.name : lhs.weight > rhs.weight
        }
        let shown = min(max(limit, 1), sorted.count)
        let usesUSD = sorted.contains { $0.metrics.usageUSD != nil }
        let usesTokens = !usesUSD && sorted.contains { tokenTotal($0.metrics) > 0 }

        func label(_ metrics: BillingMetrics) -> String {
            if usesUSD { return formatUSD(metrics.usageUSD ?? 0) }
            if usesTokens { return formatTokenCount(tokenTotal(metrics)) + " tok" }
            return formatCount(metrics.requestCount) + " 次"
        }

        var result = sorted.prefix(shown).map { entry in
            ModelShare(name: entry.name,
                       valueLabel: label(entry.metrics),
                       share: min(max(entry.weight / total, 0), 1),
                       isOther: false)
        }
        let rest = sorted.dropFirst(shown)
        if !rest.isEmpty {
            let restWeight = rest.reduce(0.0) { $0 + $1.weight }
            let restMetrics = rest.reduce(BillingMetrics()) { add($0, $1.metrics) }
            result.append(ModelShare(name: "其他 " + String(rest.count) + " 个模型",
                                     valueLabel: label(restMetrics),
                                     share: min(max(restWeight / total, 0), 1),
                                     isOther: true))
        }
        return result
    }

    /// 模型权重（花费 > token > 请求数）
    static func weight(of metrics: BillingMetrics) -> Double {
        if let usd = metrics.usageUSD, usd > 0 { return usd }
        let tokens = tokenTotal(metrics)
        if tokens > 0 { return Double(tokens) }
        return Double(max(metrics.requestCount, 0))
    }

    /// token 三项合计
    static func tokenTotal(_ metrics: BillingMetrics) -> Int {
        (metrics.inputTokens ?? 0) + (metrics.cachedInputTokens ?? 0) + (metrics.outputTokens ?? 0)
    }

    /// 同名模型的两份指标累加（nil 与 0 分开：两端都 nil 才算缺失）
    static func add(_ lhs: BillingMetrics?, _ rhs: BillingMetrics) -> BillingMetrics {
        guard let lhs else { return rhs }
        func sum(_ a: Int?, _ b: Int?) -> Int? {
            guard a != nil || b != nil else { return nil }
            return (a ?? 0) + (b ?? 0)
        }
        let usd: Double?
        if lhs.usageUSD == nil && rhs.usageUSD == nil {
            usd = nil
        } else {
            usd = (lhs.usageUSD ?? 0) + (rhs.usageUSD ?? 0)
        }
        return BillingMetrics(requestCount: lhs.requestCount + rhs.requestCount,
                              usageUSD: usd,
                              inputTokens: sum(lhs.inputTokens, rhs.inputTokens),
                              cachedInputTokens: sum(lhs.cachedInputTokens, rhs.cachedInputTokens),
                              outputTokens: sum(lhs.outputTokens, rhs.outputTokens))
    }
}
