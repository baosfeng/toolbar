import Foundation
import NetworkMonitorCore

// MARK: - Token 页派生计算测试（TokenDerive：桶序列 / 合计 / 命中率 / 累计 / 峰值 / 分族卡）
//
// 这些派生计算原先在 app target，TestRunner 只 link Core，因此长期零单测覆盖；
// 本轮下沉到 NetworkMonitorCore 并改用 package 访问级别，测试与 app 视图读到的是同一份实现。
// 展示层其余用例见 TokenPresentationTests.swift。

/// 构造只带指定字段的快照（其余字段取空态）
func tokenSnapshot(todayHourly: [HarnessHourlyUsage] = HarnessHourlyUsage.emptyDay(),
                   yesterdayHourly: [HarnessHourlyUsage] = HarnessHourlyUsage.emptyDay(),
                   daily: [HarnessDailyUsage] = [],
                   projects: [HarnessProjectUsage] = [],
                   models: [HarnessModelUsage] = [],
                   indexedSessions: Int = 0,
                   allTime: HarnessTokenUsage = .zero) -> HarnessUsageSnapshot {
    HarnessUsageSnapshot(
        totals: HarnessUsageTotals(today: .zero, thisWeek: .zero, allTime: allTime, cacheHitRate: nil),
        daily: daily,
        todayHourly: todayHourly,
        yesterdayHourly: yesterdayHourly,
        projects: projects,
        models: models,
        indexedSessions: indexedSessions,
        totalSessions: indexedSessions,
        lastScanAt: nil,
        indexingState: .ready,
        sourceAvailability: .available(toolPath: "/usr/local/bin/zstd"))
}

/// 构造单个桶
func tokenBucket(_ label: String, uncached: Int, output: Int, cache: Int, request: Int) -> TokenBucket {
    TokenBucket(label: label, uncached: uncached, output: output, cache: cache, request: request)
}

/// 一天三段的样例桶（合计 6000 tok / 240 请求）
let sampleCurrent = tokenBucket("", uncached: 1_000, output: 2_000, cache: 3_000, request: 240)
/// 上一周期样例桶（合计 3000 tok / 120 请求）
let samplePrevious = tokenBucket("", uncached: 500, output: 1_000, cache: 1_500, request: 120)

// MARK: - 小时桶

private func testHourlyBuckets() {
    var hourly = HarnessHourlyUsage.emptyDay()
    hourly[3] = HarnessHourlyUsage(hour: 3, usage: HarnessTokenUsage(uncachedInput: 10, output: 5, cacheRead: 100, requestCount: 2))
    hourly[23] = HarnessHourlyUsage(hour: 23, usage: HarnessTokenUsage(uncachedInput: 1, output: 2, cacheRead: 3, requestCount: 1))

    let buckets = TokenDerive.todayBuckets(tokenSnapshot(todayHourly: hourly))
    assertEqual(buckets.count, 24, "小时桶固定 24 个")
    assertEqual(buckets[0].label, "0时", "首桶标签为 i 时")
    assertEqual(buckets[23].label, "23时", "末桶标签为 i 时")
    assertEqual(buckets[3].uncached, 10, "3 时未缓存输入")
    assertEqual(buckets[3].cache, 100, "3 时缓存读")
    assertEqual(buckets[3].total, 115, "3 时三段合计")
    assertEqual(buckets[3].request, 2, "3 时请求数")
    assertEqual(buckets[5].total, 0, "缺省小时补 0 桶")
    assertEqual(buckets[5].request, 0, "缺省小时请求数为 0")
    assertEqual(buckets[23].output, 2, "23 时输出")

    var yesterday = HarnessHourlyUsage.emptyDay()
    yesterday[8] = HarnessHourlyUsage(hour: 8, usage: HarnessTokenUsage(uncachedInput: 4, output: 0, cacheRead: 6, requestCount: 1))
    let previous = TokenDerive.yesterdayBuckets(tokenSnapshot(yesterdayHourly: yesterday))
    assertEqual(previous.count, 24, "昨日桶固定 24 个")
    assertEqual(previous[8].cache, 6, "昨日 8 时缓存读")
    assertEqual(previous[9].total, 0, "昨日缺省小时补 0")
    print("✅ Token 小时桶（24 桶 / 缺省补 0 / i 时标签）works")
}

// MARK: - 天桶

private func testDailyBuckets() {
    let todayKey = HarnessTokenTimeWindow.dayKey(for: Date())
    let windowKeys = TokenFormat.dayKeys(lastDay: todayKey, days: 7)
    let twoDaysAgo = TokenFormat.dayKey(offsetDays: -2, from: todayKey)
    let daily = [HarnessDailyUsage(day: twoDaysAgo,
                                   usage: HarnessTokenUsage(uncachedInput: 100, output: 10, cacheRead: 900, requestCount: 4))]

    let buckets = TokenDerive.dailyBuckets(tokenSnapshot(daily: daily), days: 7)
    assertEqual(buckets.count, 7, "近 7 天 7 桶")
    assertEqual(buckets.map(\.label), windowKeys.map(TokenFormat.mmdd), "日期标签与窗口逐格对齐")
    assertEqual(buckets.last?.label, TokenFormat.mmdd(todayKey), "末桶为今日")
    assertEqual(buckets[4].cache, 900, "两天前的数据落在倒数第 3 桶")
    assertEqual(buckets[4].total, 1_010, "有数据日三段合计")
    assertEqual(buckets[3].total, 0, "无数据日补 0 桶")
    assertEqual(buckets[5].request, 0, "无数据日请求数为 0")

    let previous = TokenDerive.previousDailyBuckets(tokenSnapshot(daily: daily), days: 7)
    let previousLast = TokenFormat.dayKey(offsetDays: -7, from: todayKey)
    assertEqual(previous.count, 7, "上一周期同为 7 桶")
    assertEqual(previous.last?.label, TokenFormat.mmdd(previousLast), "上一周期终点回溯一个窗口")
    assertEqual(previous.reduce(0) { $0 + $1.total }, 0, "上一周期不含本窗口数据")
    print("✅ Token 天桶（补零 / 标签对齐 / 上一周期回溯）works")
}

// MARK: - 合计 / 命中率 / 累计 / 峰值

private func testBucketMath() {
    let first = tokenBucket("1时", uncached: 1, output: 2, cache: 3, request: 4)
    let second = tokenBucket("2时", uncached: 10, output: 20, cache: 30, request: 40)
    let total = TokenDerive.sum([first, second])
    assertEqual(total.uncached, 11, "未缓存三段分别相加")
    assertEqual(total.output, 22, "输出分别相加")
    assertEqual(total.cache, 33, "缓存读分别相加")
    assertEqual(total.request, 44, "请求数分别相加")
    assertEqual(total.label, "", "合计桶不带标签")
    assertEqual(total.total, 66, "三段合计")
    assertEqual(TokenDerive.sum([]).total, 0, "空序列合计为 0")
    assertEqual(TokenDerive.totalTokens(first), 6, "单桶三段合计")

    assertEqual(TokenDerive.hitRate(tokenBucket("", uncached: 100, output: 1_000, cache: 100, request: 1)), 0.5,
                "缓存读 ÷（缓存读 + 未缓存输入），输出不进分母")
    assertEqual(TokenDerive.hitRate(tokenBucket("", uncached: 0, output: 50, cache: 0, request: 1)), 0,
                "分母为 0 返回 0")
    assertEqual(TokenDerive.hitRate(tokenBucket("", uncached: 0, output: 0, cache: 7, request: 0)), 1,
                "全命中为 100%")
    assertEqual(TokenDerive.hitRate(.empty), 0, "空桶命中率为 0")

    let series = [tokenBucket("a", uncached: 1, output: 1, cache: 1, request: 10),
                  tokenBucket("b", uncached: 2, output: 2, cache: 2, request: 20)]
    assertEqual(TokenDerive.cumulative(series, metric: .total), [3, 9], "累计按桶逐段相加")
    assertEqual(TokenDerive.cumulative(series, metric: .request), [10, 30], "请求数累计")
    assertEqual(TokenDerive.cumulative(series, metric: .total).last, Double(TokenDerive.metricTotal(series, metric: .total)),
                "累计末值等于该指标总量")
    assertEqual(TokenDerive.metricTotal(series, metric: .request), 30, "请求数总量")
    assertEqual(TokenDerive.cumulative([], metric: .total).isEmpty, true, "空序列累计为空")

    let peak = TokenDerive.peakBucket([])
    assertEqual(peak.index, 0, "空序列峰值索引为 0")
    assertEqual(peak.bucket.total, 0, "空序列峰值桶为空")
    let peaked = TokenDerive.peakBucket([tokenBucket("a", uncached: 1, output: 0, cache: 0, request: 9),
                                         tokenBucket("b", uncached: 9, output: 0, cache: 0, request: 1),
                                         tokenBucket("c", uncached: 4, output: 0, cache: 0, request: 5)])
    assertEqual(peaked.index, 1, "取总 tok 最大的桶")
    assertEqual(peaked.bucket.total, 9, "峰值桶数值")
    print("✅ Token 合计 / 命中率 / 累计 / 峰值 works")
}

// MARK: - 分族卡

private func testFamilyCards() {
    let cards = TokenDerive.familyCards(range: .today, buckets: [sampleCurrent], prevBuckets: [samplePrevious],
                                        total: sampleCurrent, prevTotal: samplePrevious)
    assertEqual(cards.count, 4, "四族卡")
    assertEqual(cards.first { $0.metric == .request }?.unit, "次", "请求数卡单位是次")
    assertEqual(cards.first { $0.metric == .request }?.value, "240", "请求数卡取千分位整数")
    assertEqual(cards.first { $0.metric == .request }?.aux, "↑ +100.0% · 10.0/h",
                "请求数卡走「次/h」而不是占比")
    assertEqual(cards.first { $0.metric == .uncached }?.aux, "↑ +100.0% · 占 16.7%", "未缓存卡带占比")
    assertEqual(cards.first { $0.metric == .cache }?.aux, "↑ +100.0% · 占 50.0%", "缓存卡带占比")
    assertEqual(cards.first { $0.metric == .cache }?.hasDelta, true, "今日卡有同比")
    assertEqual(cards.first { $0.metric == .uncached }?.series, [1_000], "sparkline 序列按桶取该指标")

    let month = TokenDerive.familyCards(range: .d30, buckets: [sampleCurrent], prevBuckets: [samplePrevious],
                                        total: sampleCurrent, prevTotal: samplePrevious)
    assertEqual(month.allSatisfy { !$0.hasDelta }, true, "d30 无同比文案")
    assertEqual(month.first { $0.metric == .cache }?.aux.hasPrefix("日均 "), true, "d30 改用日均文案")

    let weekNoPrevious = TokenDerive.familyCards(range: .d7, buckets: [sampleCurrent], prevBuckets: [],
                                                 total: sampleCurrent, prevTotal: .empty)
    assertEqual(weekNoPrevious.allSatisfy { !$0.hasDelta }, true, "上一周期为 0 时不出同比")
    let week = TokenDerive.familyCards(range: .d7, buckets: [sampleCurrent], prevBuckets: [samplePrevious],
                                       total: sampleCurrent, prevTotal: samplePrevious)
    assertEqual(week.first { $0.metric == .request }?.hasDelta, true, "d7 有上一周期时出同比")
    print("✅ Token 分族卡（次/h · 占 x% · d7/d30 同比文案）works")
}

func runTokenDeriveTests() {
    print("\n🧪 Testing Token 页派生计算（下沉到 Core 的桶序列与分族卡）...")
    testHourlyBuckets()
    testDailyBuckets()
    testBucketMath()
    testFamilyCards()
    print("✅ Token 页派生计算 works")
}
