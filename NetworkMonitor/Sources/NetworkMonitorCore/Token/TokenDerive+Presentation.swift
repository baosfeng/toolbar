import Foundation

extension TokenDerive {
    // MARK: - 分族卡

    package static func familyCards(range: TokenRange,
                            buckets: [TokenBucket],
                            prevBuckets: [TokenBucket],
                            total: TokenBucket,
                            prevTotal: TokenBucket) -> [TokenFamilyCard] {
        let denominator = max(total.total, 1)
        let hours = range == .today ? 24 : range.days
        let hasYoy = range == .today || range == .d7
        return TokenMetric.allCases.map { metric in
            let series = buckets.map { Double(metricValue($0, metric: metric)) }
            let current = metricValue(total, metric: metric)
            let previous = metricValue(prevTotal, metric: metric)
            let delta = hasYoy ? TokenFormatting.delta(current: current, previous: previous) : nil
            // 同比与占比合并成一行（卡片只剩「大数字 + 一行辅助」），省一行高度给字号
            let head = delta?.text ?? ("日均 " + TokenFormatting.abbreviated(Double(current) / Double(hours)))
            let share: String
            if metric == .request {
                share = TokenFormatting.decimal(Double(current) / Double(hours)) + "/h"
            } else {
                share = "占 " + TokenFormatting.percent(Double(current) / Double(denominator))
            }
            return TokenFamilyCard(
                metric: metric,
                title: metric.title,
                value: metric == .request
                    ? TokenFormatting.grouped(current)
                    : TokenFormatting.splitTokens(current).number,
                unit: metric == .request ? "次" : TokenFormatting.splitTokens(current).unit,
                aux: head + " · " + share,
                deltaUp: delta?.up ?? true,
                hasDelta: delta != nil,
                series: series)
        }
    }

    /// 首屏 Hero：当前范围三项合计 + 较昨日（或上一周期）+ 实时时间
    package static func hero(range: TokenRange, current: TokenBucket, previous: TokenBucket, clock: String) -> TokenHero {
        let split = TokenFormatting.splitTokens(current.total)
        let delta = TokenFormatting.delta(current: current.total, previous: previous.total)
        let other = range == .today ? "昨日" : "上期"
        return TokenHero(title: range == .today ? "今日总消耗" : range.title + "总消耗",
                         value: split.number,
                         unit: split.unit,
                         delta: "较" + other + " " + (delta?.text ?? "—"),
                         deltaUp: delta?.up ?? true,
                         hasDelta: delta != nil,
                         clock: "实时 " + clock)
    }

    package static func metricValue(_ bucket: TokenBucket, metric: TokenMetric) -> Int {
        switch metric {
        case .uncached: return bucket.uncached
        case .output: return bucket.output
        case .cache: return bucket.cache
        case .request: return bucket.request
        }
    }

    // MARK: - 主图标题 / 说明 / 图例

    package static func bucketTitle(range: TokenRange, hourScope: TokenHourScope, hourView: TokenHourView) -> String {
        guard range == .today else { return range == .d7 ? "近 7 天 · 按天" : "近 30 天 · 按天" }
        if hourView == .compare {
            return hourScope.title + " 对比 " + hourScope.otherTitle + " · 24 桶"
        }
        return hourScope.title + " · 按小时 24 桶"
    }

    package static func bucketMeta(range: TokenRange,
                           buckets: [TokenBucket],
                           prev: [TokenBucket],
                           hourScope: TokenHourScope,
                           hourView: TokenHourView,
                           metric: TokenChartMetric) -> String {
        let current = sum(buckets)
        let previous = sum(prev)
        let format: (Int) -> String = { value in
            metric == .total ? TokenFormatting.tokens(value) : TokenFormatting.grouped(value) + " 次"
        }
        if hourView == .compare, range != .d30 {
            return "峰 " + format(metricTotal(buckets, metric: metric)) + " · "
                + hourScope.otherTitle + " " + format(metricTotal(prev, metric: metric))
        }
        if metric == .request {
            guard range == .today else { return "共 " + format(current.request) }
            let peak = peakBucket(buckets)
            return "峰 " + TokenFormatting.grouped(peak.bucket.request) + " 次@" + String(peak.index) + "时"
        }
        return "累计 " + format(totalForDisplay(buckets, metric: metric))
    }

    package static func bucketLegend(range: TokenRange,
                             total: TokenBucket,
                             prev: TokenBucket,
                             hourScope: TokenHourScope,
                             hourView: TokenHourView,
                             metric: TokenChartMetric) -> [(title: String, value: String)] {
        if hourView == .compare, range != .d30 {
            return [(hourScope.title, TokenFormatting.tokens(total.total)),
                    (hourScope.otherTitle, TokenFormatting.tokens(prev.total))]
        }
        if metric == .request {
            var items: [(String, String)] = [(hourScope.title + " 请求", TokenFormatting.grouped(total.request))]
            if range == .today {
                items.append((hourScope.otherTitle, TokenFormatting.grouped(prev.request)))
            }
            return items
        }
        var items: [(String, String)] = [("缓存读", TokenFormatting.tokens(total.cache)),
                                         ("未缓存", TokenFormatting.tokens(total.uncached)),
                                         ("输出", TokenFormatting.tokens(total.output))]
        if range == .today {
            items.append(("累计", TokenFormatting.tokens(total.total)))
        }
        return items
    }

    package static func totalForDisplay(_ buckets: [TokenBucket], metric: TokenChartMetric) -> Int {
        let bucket = sum(buckets)
        return metric == .total ? bucket.total : bucket.request
    }

    /// 峰值桶（按总 tok 计）
    package static func peakBucket(_ buckets: [TokenBucket], metric: TokenMetric = .uncached) -> (index: Int, bucket: TokenBucket) {
        var best = 0
        for index in buckets.indices where metricIndex(buckets[index]) > metricIndex(buckets[max(best, 0)]) {
            best = index
        }
        return (best, buckets.isEmpty ? .empty : buckets[best])
    }

    package static func metricIndex(_ bucket: TokenBucket) -> Int { bucket.total }

    // MARK: - 天趋势 / 分布 / 对比 / 状态带

    package static func trendMeta(_ snapshot: HarnessUsageSnapshot) -> String {
        let buckets = dailyBuckets(snapshot, days: 14)
        let total = sum(buckets).total
        return "不随范围 · 日均 " + TokenFormatting.tokens(Int(Double(total) / 14.0))
    }

    package static func projectRows(_ snapshot: HarnessUsageSnapshot) -> [TokenDistroRow] {
        let total = snapshot.projects.reduce(0) { $0 + $1.usage.totalTokens }
        return snapshot.projects.enumerated().map { index, item in
            let tokens = item.usage.totalTokens
            let share = total > 0 ? Double(tokens) / Double(total) : 0
            return TokenDistroRow(rank: index + 1,
                                  name: item.displayName,
                                  provider: "",
                                  sub: "\(item.sessionCount) 会话 · 占 " + TokenFormatting.percent(share),
                                  amount: TokenFormatting.tokens(tokens),
                                  share: share,
                                  colorIndex: index)
        }
    }

    package static func modelRows(_ snapshot: HarnessUsageSnapshot) -> [TokenDistroRow] {
        let total = snapshot.models.reduce(0) { $0 + $1.usage.totalTokens }
        return snapshot.models.enumerated().map { index, item in
            let tokens = item.usage.totalTokens
            let share = total > 0 ? Double(tokens) / Double(total) : 0
            let rate = HarnessCacheHitRate.compute(cacheRead: item.usage.cacheRead,
                                                   uncachedInput: item.usage.uncachedInput) ?? 0
            return TokenDistroRow(rank: index + 1,
                                  name: item.model,
                                  provider: item.provider,
                                  sub: "provider " + (item.provider.isEmpty ? "—" : item.provider)
                                      + " · 占 " + TokenFormatting.percent(share)
                                      + " · 命中 " + TokenFormatting.percent(rate),
                                  amount: TokenFormatting.tokens(tokens),
                                  share: share,
                                  colorIndex: index)
        }
    }

    package static func compare(_ snapshot: HarnessUsageSnapshot,
                        current: TokenBucket,
                        previous: TokenBucket,
                        range: TokenRange) -> TokenPaneModel.TokenCompare? {
        guard range != .d30 else { return nil }
        let currentAll = current.total
        let previousAll = previous.total
        guard previousAll > 0 else { return nil }
        let scale = Double(max(currentAll, previousAll))
        let delta = TokenFormatting.delta(current: currentAll, previous: previousAll)
        return TokenPaneModel.TokenCompare(
            currentLabel: range == .today ? "今日" : "本周期",
            previousLabel: range == .today ? "昨日" : "上一周期",
            currentText: TokenFormatting.tokens(currentAll),
            previousText: TokenFormatting.tokens(previousAll),
            currentFraction: Double(currentAll) / scale,
            previousFraction: Double(previousAll) / scale,
            deltaText: delta?.text ?? "持平",
            deltaUp: delta?.up ?? true)
    }

    package static func stateBand(_ snapshot: HarnessUsageSnapshot,
                          range: TokenRange,
                          buckets: [TokenBucket],
                          previous: TokenBucket,
                          current: TokenBucket) -> [TokenStateItem] {
        let peak = peakBucket(buckets)
        let peakText = range == .today
            ? "\(TokenFormatting.grouped(peak.bucket.request)) 次@\(peak.index)时"
            : TokenFormatting.tokens(sum(buckets).total)
        // 字号提到 10pt 后 4 格在 296pt 内会挤成截断；「索引」与页头「DSH · N 会话」同值，去掉重复项
        return [
            TokenStateItem(title: "峰", value: peakText, tone: .request),
            TokenStateItem(title: "昨", value: TokenFormatting.tokens(previous.total), tone: .accent),
            TokenStateItem(title: "缓存", value: TokenFormatting.tokens(current.cache), tone: .cache),
        ]
    }
}
