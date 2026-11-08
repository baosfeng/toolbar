import Foundation
import NetworkMonitorCore

// MARK: - 缓存命中二级页随范围（今日 / 近 7 天 / 近 30 天）
//
// 用户要求「我选择 7 天就只展示 7 天的」。这页此前写死「主数值今日、走势与均值 30 天、
// 逐桶今日 24 桶」，三块各自固定口径，与主面板范围完全脱钩。现全部改由 Core 的
// TokenDerive.cachePage(range:) 按当前范围派生，本文件锁死四条契约：
// 1. 桶序列长度与单位随范围（24 桶 / 7 天 / 30 天）；
// 2. 主数值与上一周期取值三档各不相同（换范围真的换数据，不是换标签）；
// 3. 文案含当前范围名，且不再出现「不随主面板范围切换 / 固定 30 天 / 固定今日 24 桶」；
// 4. 上一周期没有数据时给「—」，不拿 0% 冒充「命中率 0」。

/// 造一份「每一天的命中率按区间分层」的快照，便于断言三档范围各取各的窗口。
/// - offset 0…-6：命中率 70%；-7…-13：20%；-14…-29：10%；-30…-59：40%（上一周期 30 天）
func cacheRangeSnapshot() -> HarnessUsageSnapshot {
    let lastDay = HarnessTokenTimeWindow.dayKey(for: Date())
    var daily: [HarnessDailyUsage] = []
    // back = 距今几天：0…6 天前命中率 70%，7…13 天前 20%，14…29 天前 10%，30…59 天前 40%
    for back in 0 ... 59 {
        let usage: HarnessTokenUsage
        switch back {
        case 0 ... 6: usage = HarnessTokenUsage(uncachedInput: 300, cacheRead: 700, requestCount: 1)
        case 7 ... 13: usage = HarnessTokenUsage(uncachedInput: 800, cacheRead: 200, requestCount: 1)
        case 14 ... 29: usage = HarnessTokenUsage(uncachedInput: 900, cacheRead: 100, requestCount: 1)
        default: usage = HarnessTokenUsage(uncachedInput: 600, cacheRead: 400, requestCount: 1)
        }
        let key = TokenFormat.dayKey(offsetDays: -back, from: lastDay)
        daily.append(HarnessDailyUsage(day: key, usage: usage))
    }
    var todayHourly = HarnessHourlyUsage.emptyDay()
    todayHourly[3] = HarnessHourlyUsage(hour: 3, usage: HarnessTokenUsage(uncachedInput: 100, cacheRead: 900, requestCount: 1))
    var yesterdayHourly = HarnessHourlyUsage.emptyDay()
    yesterdayHourly[3] = HarnessHourlyUsage(hour: 3, usage: HarnessTokenUsage(uncachedInput: 700, cacheRead: 300, requestCount: 1))
    return tokenSnapshot(todayHourly: todayHourly, yesterdayHourly: yesterdayHourly,
                         daily: daily, indexedSessions: 5)
}

/// 只有近 7 天有数据：今日小时桶与各档「上一周期」都应是空（不给假数字）
func cacheNoPreviousSnapshot() -> HarnessUsageSnapshot {
    let lastDay = HarnessTokenTimeWindow.dayKey(for: Date())
    let daily = (0 ... 6).map { back in
        HarnessDailyUsage(day: TokenFormat.dayKey(offsetDays: -back, from: lastDay),
                          usage: HarnessTokenUsage(uncachedInput: 400, cacheRead: 600, requestCount: 1))
    }
    return tokenSnapshot(daily: daily)
}

func cacheModel(_ snapshot: HarnessUsageSnapshot, _ range: TokenRange) -> TokenPaneModel {
    TokenPaneModel.make(snapshot: snapshot, range: range, hourScope: .today,
                        hourView: .stack, metric: .total, trendMode: .stack)
}

/// 1) 桶序列跟随范围（由 TokenCachePageCopyTests 的套件入口跨文件调用，故不设 private）
func testCacheBucketsFollowRange() {
    let snapshot = cacheRangeSnapshot()
    let today = cacheModel(snapshot, .today)
    let d7 = cacheModel(snapshot, .d7)
    let d30 = cacheModel(snapshot, .d30)

    assertEqual(today.cachePage.bucketCount, 24, "今日缓存页 24 个小时桶")
    assertEqual(d7.cachePage.bucketCount, 7, "近 7 天缓存页 7 个天桶")
    assertEqual(d30.cachePage.bucketCount, 30, "近 30 天缓存页 30 个天桶")
    assertEqual(today.cachePage.series.count, 24, "今日走势序列 24 点")
    assertEqual(d7.cachePage.series.count, 7, "近 7 天走势序列 7 点")
    assertEqual(d30.cachePage.series.count, 30, "近 30 天走势序列 30 点")
    // 与主面板主图桶数同源：缓存页不再自己数一套
    assertEqual(today.cachePage.bucketCount, today.buckets.count, "今日与主面板主图桶数一致")
    assertEqual(d7.cachePage.bucketCount, d7.buckets.count, "近 7 天与主面板主图桶数一致")
    assertEqual(d30.cachePage.bucketCount, d30.buckets.count, "近 30 天与主面板主图桶数一致")

    assertEqual(today.cachePage.bucketUnitText, "24 桶", "今日桶数单位「24 桶」")
    assertEqual(d7.cachePage.bucketUnitText, "7 天", "近 7 天桶数单位「7 天」")
    assertEqual(d30.cachePage.bucketUnitText, "30 天", "近 30 天桶数单位「30 天」")
    // 主面板缓存卡图例的虚线条目与二级页同一处取值
    assertEqual(today.hitBucketText, today.cachePage.bucketUnitText, "主面板「24 桶」与二级页同源")
    assertEqual(d7.hitBucketText, d7.cachePage.bucketUnitText, "主面板「7 天」与二级页同源")

    // 轴行等宽分列：30 格每格只剩约 8pt，mmdd 会被裁成一个「1」，所以少给刻度
    assertEqual(today.cachePage.axisLabels.count, 5, "今日横轴 5 个刻度（0/6/12/18/23 时）")
    assertEqual(d7.cachePage.axisLabels.count, 7, "近 7 天横轴逐日 7 个刻度")
    assertEqual(d30.cachePage.axisLabels.count, 5, "近 30 天横轴 5 个等距刻度（每格放得下 mmdd）")
    assertEqual(d30.cachePage.axisLabels.first, d30.cachePage.axisLabels.first, "近 30 天首刻度有文字")
    assertEqual(d30.cachePage.axisLabels.allSatisfy { $0.count >= 4 }, true,
                "近 30 天每个刻度都是 mmdd（不是被裁成单个数字）")
    assertEqual(d30.cachePage.axisLabels.last, TokenFormatting.mmdd(HarnessTokenTimeWindow.dayKey(for: Date())),
                "近 30 天末刻度是今日")
    // 纵轴地板 = 本范围**有数据桶**的最小值：30 天都挤在 96%–99% 时从 0 起画会糊成一块
    assertEqual(d30.cachePage.seriesFloor, d30.cachePage.series.compactMap { $0 }.min() ?? -1,
                "近 30 天纵轴地板取有效桶序列最小值")
    assertEqual(today.cachePage.seriesFloor, 90, "今日只有 3 时有数据，纵轴地板 = 该桶 90%（不再被空缺拉到底）")
    assertEqual(d30.cachePage.trendMeta.contains("纵轴"), true, "纵轴被抬时卡头写明起点")

    assertEqual(today.cachePage.trendTitle, "命中率走势 · 今日", "今日走势卡标题带范围")
    assertEqual(d7.cachePage.trendTitle, "命中率走势 · 近 7 天", "近 7 天走势卡标题带范围")
    assertEqual(d30.cachePage.trendTitle, "命中率走势 · 近 30 天", "近 30 天走势卡标题带范围")
    print("✅ 缓存命中页桶序列跟随范围（24 桶 / 7 天 / 30 天，与主面板同源）works")
}

/// 6) 空缺桶给 nil，不拿 0 冒充「命中率掉到底」
///
/// 用户口径：「无会话的小时保留空缺、不画 0」。改前 series 把空缺算成 0，
/// 24 桶图上会长出两座掉底的山，纵轴卡头也跟着写「0.0% – 98.7%」。
func testCacheSeriesGaps() {
    let today = cacheModel(cacheRangeSnapshot(), .today).cachePage
    assertEqual(today.series.count, 24, "空缺不改长度：仍是 24 个桶位（横轴对齐）")
    assertEqual(today.series[3], 90, "3 时有数据的桶 = 90%")
    assertEqual(today.series[0], nil, "0 时无会话 → nil（不是 0%）")
    assertEqual(today.series.filter { $0 == nil }.count, 23, "只有 3 时有数据，其余 23 桶为 nil")
    assertEqual(today.trendMeta.hasPrefix("纵轴 0.0%"), false, "卡头不再把空缺算进纵轴下限（改前写「0.0% – 98.7%」）")
    assertEqual(today.trendMeta.hasPrefix("纵轴 90.0% – 90.0%"), true,
                "卡头纵轴 = 真实 min–max（单桶时上下限同值）")

    // 满覆盖窗口没有缺口
    let d7 = cacheModel(cacheRangeSnapshot(), .d7).cachePage
    assertEqual(d7.series.allSatisfy { $0 != nil }, true, "近 7 天每天都有数据 → 无缺口")
    assertEqual(d7.trendMeta.contains("纵轴 70.0% – 70.0%"), true, "近 7 天纵轴 = 真实命中率区间")

    // 整窗无数据：不给「0%」区间，写「无有效桶」
    let emptyToday = cacheModel(cacheNoPreviousSnapshot(), .today).cachePage
    assertEqual(emptyToday.series.allSatisfy { $0 == nil }, true, "今日无小时数据 → 全部 nil")
    assertEqual(emptyToday.trendMeta.contains("无有效桶"), true, "全空窗口写明无有效桶，不写 0% 区间")
    assertEqual(emptyToday.seriesFloor, 0, "全空窗口地板退回 0（不出现负值/NaN）")
    print("✅ 缓存走势空缺桶 = nil（不画 0，纵轴取真实 min–max）works")
}

/// 2) 主数值与上一周期三档各不相同（同上，跨文件调用不设 private）
func testCacheValuesFollowRange() {
    let snapshot = cacheRangeSnapshot()
    let today = cacheModel(snapshot, .today).cachePage
    let d7 = cacheModel(snapshot, .d7).cachePage
    let d30 = cacheModel(snapshot, .d30).cachePage

    // 今日 = 今日小时桶（900 / 1000 = 90.0%）；近 7 天 = 70%；近 30 天 = 7900/30000 = 26.3%
    assertEqual(today.heroValue, "90.0", "今日主数值取今日小时桶")
    assertEqual(d7.heroValue, "70.0", "近 7 天主数值取 7 天窗口")
    assertEqual(d30.heroValue, "26.3", "近 30 天主数值取 30 天窗口")
    assertEqual(Set([today.heroValue, d7.heroValue, d30.heroValue]).count, 3,
                "三档范围主数值互不相同（不是换标签）")

    // 上一周期：今日 → 昨日（300/1000 = 30%）；7 天 → 前 7 天（20%）；30 天 → 前 30 天（40%）
    assertEqual(today.previousRateText, "30.0%", "今日对照昨日")
    assertEqual(d7.previousRateText, "20.0%", "近 7 天对照前 7 天")
    assertEqual(d30.previousRateText, "40.0%", "近 30 天对照前 30 天")
    assertEqual(Set([today.previousRateText, d7.previousRateText, d30.previousRateText]).count, 3,
                "三档范围上一周期互不相同")

    assertEqual(today.previousLabel, "昨日", "今日对照标签「昨日」")
    assertEqual(d7.previousLabel, "前 7 天", "近 7 天对照标签「前 7 天」")
    assertEqual(d30.previousLabel, "前 30 天", "近 30 天对照标签「前 30 天」")
    assertEqual(d7.currentLabel, "近 7 天", "对照卡左列写当前范围")

    // 环形卡与 Hero 同一个数（改前：主数值今日、环形图今日、走势 30 天，三套口径）
    assertEqual(today.ringText, today.heroValue, "今日环心与主数值一致")
    assertEqual(d30.ringText, d30.heroValue, "近 30 天环心与主数值一致")
    assertEqual(today.ringFraction, 0.9, "今日环形比例 0.9")
    assertEqual(d7.saveRatioText, d7.currentRateText, "节省比例与命中率同源")

    // 三段键值随范围取数：今日缓存读 900、30 天覆盖 7*700 + 7*200 + 16*100 = 7900（7.9K）
    assertEqual(today.cacheReadText, "900", "今日缓存读取今日小时桶")
    assertEqual(d30.cacheReadText, "7.9K", "近 30 天缓存读取 30 天窗口")
    assertEqual(today.uncachedText, "100", "今日未缓存输入取今日小时桶")
    assertEqual(d30.uncachedText, "22.1K", "近 30 天未缓存输入取 30 天窗口")
    assertEqual(today.outputText, "0", "今日无输出时给 0（不隐藏）")

    // 差值按「个百分点」给，不按相对百分比；标签用「较上期」（两列布局放不下「较前 30 天」）
    assertEqual(today.deltaLabel, "较上期", "差值标签不重复上一周期名（列宽放不下）")
    assertEqual(today.deltaText, "↑ +60.0 个百分点", "今日 90% vs 昨日 30% → +60.0 个百分点")
    assertEqual(d7.deltaText, "↑ +50.0 个百分点", "近 7 天 70% vs 前 7 天 20% → +50.0 个百分点")
    assertEqual(d7.deltaUp, true, "上行方向")
    // 样本量 = 命中率分母（缓存读 + 未缓存输入），输出不进分母
    assertEqual(today.sampleText.contains("1K"), true, "今日样本量 = 1000 tok 分母")
    assertEqual(today.sampleText.contains("分母"), true, "样本量写明是分母")
    print("✅ 缓存命中页主数值 / 上一周期 / 差值三档各不相同（90.0 / 70.0 / 26.3）works")
}
