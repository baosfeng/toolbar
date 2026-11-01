import Foundation

// MARK: - Token 页派生计算（从 TokenPaneModel.make 抽出：单文件体积门禁要求）

/// 所有「范围 / 桶 / 占比 / 同比 / 分布」的派生计算集中在这里，视图层只排版
package enum TokenDerive {

    // MARK: - 桶序列

    /// 今日 00–23 共 24 桶（缺省小时补 0 桶，标签 i 时）
    package static func todayBuckets(_ snapshot: HarnessUsageSnapshot) -> [TokenBucket] {
        hourlyBuckets(snapshot.todayHourly)
    }

    /// 昨日 00–23 共 24 桶
    package static func yesterdayBuckets(_ snapshot: HarnessUsageSnapshot) -> [TokenBucket] {
        hourlyBuckets(snapshot.yesterdayHourly)
    }

    /// 最近 N 天（含今日）按天桶；无数据日补 0 桶并保留日期标签
    package static func dailyBuckets(_ snapshot: HarnessUsageSnapshot, days: Int) -> [TokenBucket] {
        let map = dayMap(snapshot)
        let lastDay = HarnessTokenTimeWindow.dayKey(for: Date())
        return TokenFormat.dayKeys(lastDay: lastDay, days: days).map { key in
            TokenBucket(label: TokenFormatting.mmdd(key), usage: map[key])
        }
    }

    /// 上一周期按天桶（7 / 30 天窗口的对照；索引只回溯 33 天时可能为空）
    package static func previousDailyBuckets(_ snapshot: HarnessUsageSnapshot, days: Int) -> [TokenBucket] {
        let map = dayMap(snapshot)
        let lastDay = HarnessTokenTimeWindow.dayKey(for: Date())
        let anchor = TokenFormat.dayKey(offsetDays: -days, from: lastDay)
        return TokenFormat.dayKeys(lastDay: anchor, days: days).map { key in
            TokenBucket(label: TokenFormatting.mmdd(key), usage: map[key])
        }
    }

    package static func sum(_ buckets: [TokenBucket]) -> TokenBucket {
        var uncached = 0, output = 0, cache = 0, request = 0
        for bucket in buckets {
            uncached += bucket.uncached
            output += bucket.output
            cache += bucket.cache
            request += bucket.request
        }
        return TokenBucket(label: "", uncached: uncached, output: output, cache: cache, request: request)
    }

    package static func totalTokens(_ bucket: TokenBucket) -> Int { bucket.total }

    /// 当前指标在该序列上的总量（总量取三段相加，请求数取请求数）
    package static func metricTotal(_ buckets: [TokenBucket], metric: TokenChartMetric) -> Int {
        metric == .total ? sum(buckets).total : sum(buckets).request
    }

    /// 累计序列（虚线基准用）
    package static func cumulative(_ buckets: [TokenBucket], metric: TokenChartMetric) -> [Double] {
        var running = 0.0
        return buckets.map { bucket in
            running += Double(metric == .total ? bucket.total : bucket.request)
            return running
        }
    }

    /// 命中率 0…1：缓存读 ÷（缓存读 + 未缓存输入），输出不进分母
    package static func hitRate(_ bucket: TokenBucket) -> Double {
        let denominator = bucket.cache + bucket.uncached
        guard denominator > 0 else { return 0 }
        return Double(bucket.cache) / Double(denominator)
    }

    // MARK: - 内部

    private static func hourlyBuckets(_ slots: [HarnessHourlyUsage]) -> [TokenBucket] {
        (0..<24).map { hour in
            let usage = slots.first(where: { $0.hour == hour })?.usage
            return TokenBucket(label: "\(hour)时", usage: usage)
        }
    }

    private static func dayMap(_ snapshot: HarnessUsageSnapshot) -> [String: HarnessTokenUsage] {
        snapshot.daily.reduce(into: [String: HarnessTokenUsage]()) { result, item in
            result[item.day] = item.usage
        }
    }
}
