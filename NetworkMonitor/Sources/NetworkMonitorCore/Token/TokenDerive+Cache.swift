import Foundation

// MARK: - 缓存命中页（跟随主面板范围）

/// 缓存命中二级页的全部数值与文案 —— Core 纯函数派生，视图只排版不拼口径
///
/// 存在理由：这页曾写死「主数值今日 / 走势与均值固定 30 天 / 逐桶固定今日 24 桶」，
/// 用户把主面板切到近 7 天后，页面仍是「今日 + 30 天」的混合口径，与首屏 Hero、
/// 四族卡、按项目、按模型全部对不上。现在每一块都按当前范围派生：
/// 今日 → 24 个小时桶、对照昨日；近 7 / 30 天 → 对应天桶、对照同长度的前一段。
///
/// 放在 Core 而不是视图层的理由：TestRunner 只 link Core，数值与文案的可断言性
/// 直接决定「换范围是否真的换了数据」能不能被门禁守住。
package struct TokenCachePage {

    // MARK: 范围

    /// 当前范围
    package let range: TokenRange
    /// 当前范围名（今日 / 近 7 天 / 近 30 天）
    package let rangeTitle: String
    /// 本周期名（与 rangeTitle 同值，对照卡左列用）
    package let currentLabel: String
    /// 上一周期名（昨日 / 前 7 天 / 前 30 天）
    package let previousLabel: String
    /// 当前范围的桶数：今日 24、N 天 = N
    package let bucketCount: Int
    /// 桶数文案（24 桶 / 7 天 / 30 天）
    package let bucketUnitText: String

    // MARK: 主数值（Hero + 环）

    /// 主数值（一位小数，如 97.5）
    package let heroValue: String
    /// 单位（如 % · 近 7 天命中）
    package let heroUnit: String
    /// 副标题（写明与主面板同范围 + 分母口径）
    package let heroSub: String
    /// 环形图比例（0…1）
    package let ringFraction: Double
    /// 环心文字（与 heroValue 同值）
    package let ringText: String
    /// 环的无障碍文案
    package let ringAccessibility: String

    // MARK: 三段键值

    package let cacheReadText: String
    package let uncachedText: String
    /// 节省比例（= 命中率，缓存读在输入 token 里的占比）
    package let saveRatioText: String
    package let outputText: String

    // MARK: 走势卡

    /// 当前范围逐桶命中率（%），长度 = bucketCount
    package let series: [Double]
    /// 走势卡标题（命中率走势 · 当前范围）
    package let trendTitle: String
    /// 走势卡 meta（纵轴区间 + 桶数）
    package let trendMeta: String
    /// 走势图纵轴地板（百分比值，0 = 从零起画）
    ///
    /// 30 天窗口的命中率都挤在 96%–99% 时，以 0 为地板画出来是一片实心色块，
    /// 看不出峰谷；这里给「本范围的序列最小值」，视图把 [floor, max] 铺满画布。
    /// 今日窗口含空桶（0%），floor 自然是 0，与改造前画法一致。
    package let seriesFloor: Double
    /// 走势卡横轴标签（按桶数稀释）
    package let axisLabels: [String]
    /// 走势图无障碍文案
    package let trendAccessibility: String

    // MARK: 对照卡（本周期 vs 上一周期）

    package let compareTitle: String
    package let compareMeta: String
    package let currentRateText: String
    /// 上一周期命中率；上一周期无数据时为「—」
    package let previousRateText: String
    package let currentCacheText: String
    /// 上一周期缓存读；无数据时为「—」
    package let previousCacheText: String
    /// 对照条比例（本周期 / 上一周期，按两者较大值归一，避免溢出）
    package let currentFraction: Double
    package let previousFraction: Double
    /// 命中率差值文案（个百分点）；无上一周期时为「—」
    package let deltaText: String
    package let deltaUp: Bool
    /// 样本量（缓存读 + 未缓存输入 = 命中率分母）
    package let sampleText: String
    /// 「较上一周期」标签
    package let deltaLabel: String
    /// 「节省比例」键值标签
    package let saveRatioLabel: String
    /// 上一周期是否有数据（false 时相关位置一律「—」，不编数）
    package let hasPrevious: Bool
    /// 上一周期里真正有输入数据的天数（今日范围按小时桶数计）
    package let previousDaysWithData: Int
    /// 上一周期应有天数（今日 24 小时 / N 天 N 天）
    package let previousDaysExpected: Int

    // MARK: 说明

    /// 面包屑右侧说明（当前范围口径）
    package let crumbMeta: String
    /// 底部口径说明
    package let note: String
}

extension TokenDerive {

    /// 缓存命中页：按当前范围派生全部数值与文案
    ///
    /// - 当前范围桶序列：今日 24 个小时桶；近 7 / 30 天为按天桶（含无数据的补 0 桶）；
    /// - 当前命中率 = 命中率(该序列合计)，分母只含缓存读 + 未缓存输入；
    /// - 上一周期：今日 → 昨日 24 桶；近 7 / 30 天 → 同长度前一段的天桶；
    /// - 上一周期分母为 0 时不给数字（「—」），不拿 0% 冒充「命中率 0」。
    package static func cachePage(_ snapshot: HarnessUsageSnapshot, range: TokenRange) -> TokenCachePage {
        let buckets = range == .today ? todayBuckets(snapshot) : dailyBuckets(snapshot, days: range.days)
        let previousBuckets = range == .today
            ? yesterdayBuckets(snapshot)
            : previousDailyBuckets(snapshot, days: range.days)

        let current = sum(buckets)
        let previous = sum(previousBuckets)
        let currentFraction = hitRate(current)
        let previousDenominator = previous.cache + previous.uncached
        let hasPrevious = previousDenominator > 0
        let previousFraction = hasPrevious ? Double(previous.cache) / Double(previousDenominator) : 0
        // 样本量 = 命中率分母（缓存读 + 未缓存输入）；输出不进分母
        let sample = current.cache + current.uncached
        let series = buckets.map { hitRate($0) * 100 }
        let low = series.min() ?? 0
        let high = series.max() ?? 0

        let previousLabel = range == .today ? "昨日" : "前 " + String(range.days) + " 天"
        let bucketUnit = range == .today ? "24 桶" : String(range.days) + " 天"
        // 上一周期实际有数据的天数：索引只回溯 33 天，30 天窗口的「前 30 天」往往只有几天可见，
        // 样本量小这件事要写在卡头，否则「前 30 天命中 96.4%」会被当成同样量级的结论
        let previousDaysWithData = previousBuckets.filter { $0.cache + $0.uncached > 0 }.count
        let previousDaysExpected = previousBuckets.count
        let delta = rateDelta(current: currentFraction, previous: previousFraction, hasPrevious: hasPrevious)
        let currentPercent = TokenFormatting.percent(currentFraction)

        return TokenCachePage(
            range: range,
            rangeTitle: range.title,
            currentLabel: range.title,
            previousLabel: previousLabel,
            bucketCount: buckets.count,
            bucketUnitText: bucketUnit,
            heroValue: TokenFormatting.decimal(currentFraction * 100),
            heroUnit: "% · " + range.title + "命中",
            heroSub: "缓存读 ÷（缓存读 + 未缓存输入）· 与主面板同范围（" + range.title + "）· 分母 "
                + TokenFormatting.tokens(sample) + " tok",
            ringFraction: currentFraction,
            ringText: TokenFormatting.decimal(currentFraction * 100),
            ringAccessibility: range.title + "缓存命中率 " + currentPercent,
            cacheReadText: TokenFormatting.tokens(current.cache),
            uncachedText: TokenFormatting.tokens(current.uncached),
            saveRatioText: currentPercent,
            outputText: TokenFormatting.tokens(current.output),
            series: series,
            trendTitle: "命中率走势 · " + range.title,
            // 纵轴被抬到序列最小值时，卡头必须写清起点（否则图看起来像「一路贴顶」）
            trendMeta: "纵轴 " + TokenFormatting.percent(low / 100) + " – "
                + TokenFormatting.percent(high / 100) + " · " + bucketUnit,
            seriesFloor: low,
            axisLabels: cacheAxisLabels(buckets: buckets, range: range),
            trendAccessibility: range.title + "缓存命中率走势，" + String(buckets.count) + " 个点",
            compareTitle: "对照 · " + range.title + " vs " + previousLabel,
            compareMeta: cacheCompareMeta(range: range, previousDaysWithData: previousDaysWithData,
                                          previousDaysExpected: previousDaysExpected),
            currentRateText: currentPercent,
            previousRateText: hasPrevious ? TokenFormatting.percent(previousFraction) : "—",
            currentCacheText: TokenFormatting.tokens(current.cache),
            previousCacheText: hasPrevious ? TokenFormatting.tokens(previous.cache) : "—",
            currentFraction: currentFraction,
            previousFraction: previousFraction,
            deltaText: delta?.text ?? "—",
            deltaUp: delta?.up ?? true,
            sampleText: TokenFormatting.tokens(sample) + " tok 分母",
            // 统计卡是两列布局（每列约 139pt），「较前 30 天 + ↑ +2.0 个百分点」放不下，
            // 上一周期名在同一张卡左边那格已经有了，这里只留「较上期」
            deltaLabel: "较上期",
            saveRatioLabel: "节省比例",
            hasPrevious: hasPrevious,
            previousDaysWithData: previousDaysWithData,
            previousDaysExpected: previousDaysExpected,
            crumbMeta: range.title + "口径",
            note: TokenDistroCopy.cacheNote(range: range))
    }

    /// 对照卡卡头说明
    ///
    /// 索引最多回溯 33 天，近 30 天窗口的「前 30 天」通常只有几天，样本量差一个量级。
    /// 不写这句，用户会把 3 天的 96.4% 和 30 天的 98.4% 当成同一强度的结论。
    /// 今日范围不写：24 小时里有几小时没活动是常态，不是样本缺口，写出来只会误导。
    private static func cacheCompareMeta(range: TokenRange,
                                        previousDaysWithData: Int,
                                        previousDaysExpected: Int) -> String {
        guard range != .today else { return "同时段昨日" }
        guard previousDaysWithData < previousDaysExpected else { return "同长度前一段" }
        return "前一段仅 " + String(previousDaysWithData) + "/" + String(previousDaysExpected) + " 天有数据"
    }

    /// 命中率差值：按「个百分点」给，不按相对百分比（97.0% → 98.0% 应说 +1.0 个百分点，不是 +1%）
    private static func rateDelta(current: Double, previous: Double, hasPrevious: Bool)
        -> (text: String, up: Bool)? {
        guard hasPrevious else { return nil }
        let points = (current - previous) * 100
        guard abs(points) >= 0.05 else { return ("持平", true) }
        return ((points > 0 ? "↑ +" : "↓ ") + TokenFormatting.decimal(abs(points)) + " 个百分点", points > 0)
    }

    /// 走势卡横轴标签
    ///
    /// 轴行是等宽分列（30 个格子时每格只剩约 8pt，mmdd 会被裁成一个「1」），
    /// 所以「放不下就少给刻度」而不是给一长串会被裁的空标签：
    /// - 今日：5 个时刻刻度（0 / 6 / 12 / 18 / 23 时）；
    /// - 近 7 天：逐日 7 个刻度（每格约 38pt，mmdd 放得下）；
    /// - 近 30 天：5 个等距刻度（约 1 周一个）。
    package static func cacheAxisLabels(buckets: [TokenBucket], range: TokenRange) -> [String] {
        guard !buckets.isEmpty else { return [] }
        switch range {
        case .today:
            return ["0 时", "6 时", "12 时", "18 时", "23 时"]
        case .d7:
            return buckets.map(\.label)
        case .d30:
            let count = buckets.count
            let last = count - 1
            let picks = [0, count / 4, count / 2, count * 3 / 4, last]
            return picks.map { buckets[min($0, last)].label }
        }
    }
}
