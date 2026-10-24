import Foundation
import NetworkMonitorCore

// MARK: - Token 面板展示口径测试

// 覆盖：K/M/B 缩写边界、千分位、百分比、日期窗口边界（7/30 天、跨月跨年）、
// 缺省小时口径、空态判据、环比计算（倍数 / 上涨 / 下跌 / 昨日为 0）。

private func testTokenAbbreviated() {
    assertEqual(TokenFormat.abbreviated(0), "0", "0 不带单位")
    assertEqual(TokenFormat.abbreviated(999), "999", "999 不带单位")
    assertEqual(TokenFormat.abbreviated(1_000), "1K", "1000 → 1K")
    assertEqual(TokenFormat.abbreviated(1_500), "1.5K", "1500 → 1.5K")
    assertEqual(TokenFormat.abbreviated(72_271), "72.3K", "请求数 72,271 → 72.3K")
    assertEqual(TokenFormat.abbreviated(1_000_000), "1M", "100 万 → 1M")
    assertEqual(TokenFormat.abbreviated(5_390_000), "5.39M", "小于 10M 保留 2 位")
    assertEqual(TokenFormat.abbreviated(399_200_000), "399.2M", "399.2M 量级")
    assertEqual(TokenFormat.abbreviated(10_100_000), "10.1M", "≥10M 只保留 1 位")
    assertEqual(TokenFormat.abbreviated(1_000_000_000), "1B", "10 亿 → 1B")
    assertEqual(TokenFormat.abbreviated(10_100_000_000), "10.1B", "累计缓存 10.10B")
    assertEqual(TokenFormat.grouped(72_271), "72,271", "千分位")
    assertEqual(TokenFormat.grouped(999), "999", "三位不加分隔")
    assertEqual(TokenFormat.grouped(1_234_567), "1,234,567", "多位分组")
    assertEqual(TokenFormat.percent(0.986), "98.6%", "复用率")
    assertEqual(TokenFormat.percent(nil), "—", "无数据不显示 0%")
    print("✅ Token K/M/B 缩写与格式化 works")
}

private func testTokenRangeBoundary() {
    let week = TokenFormat.dayKeys(lastDay: "2026-10-24", days: 7)
    assertEqual(week.count, 7, "近 7 天 7 格")
    assertEqual(week.first, "2026-10-18", "近 7 天起点")
    assertEqual(week.last, "2026-10-24", "近 7 天终点")

    let month = TokenFormat.dayKeys(lastDay: "2026-10-24", days: 30)
    assertEqual(month.count, 30, "近 30 天 30 格")
    assertEqual(month.first, "2026-09-25", "跨月起点")
    assertEqual(month.last, "2026-10-24", "跨月终点")

    let acrossYear = TokenFormat.dayKeys(lastDay: "2027-01-02", days: 7)
    assertEqual(acrossYear.first, "2026-12-27", "跨年回退")
    assertEqual(TokenFormat.dayKey(offsetDays: 1, from: "2026-12-31"), "2027-01-01", "跨年前进")
    assertEqual(TokenFormat.dayKey(offsetDays: -1, from: "2026-03-01"), "2026-02-28", "非闰年 2 月回退")
    assertEqual(TokenFormat.dayKey(offsetDays: -1, from: "2028-03-01"), "2028-02-29", "闰年 2 月回退")
    assertEqual(TokenFormat.dayKeys(lastDay: "2026-10-24", days: 0), [], "天数为 0 时为空窗口")
    assertEqual(TokenFormat.mmdd("2026-10-24"), "10-24", "坐标轴取月-日")
    print("✅ Token 范围窗口边界（7/30 天、跨月跨年）works")
}

private func testTokenMissingHour() {
    // 缺省小时（nil）不参与汇总；未来小时由 throughHour 截断
    var hourly = HarnessHourlyUsage.emptyDay()
    hourly[0] = HarnessHourlyUsage(hour: 0, usage: HarnessTokenUsage(uncachedInput: 10, output: 1, cacheRead: 100, requestCount: 2))
    hourly[9] = HarnessHourlyUsage(hour: 9, usage: HarnessTokenUsage(uncachedInput: 0, output: 0, cacheRead: 0, requestCount: 3))
    hourly[14] = HarnessHourlyUsage(hour: 14, usage: HarnessTokenUsage(uncachedInput: 5, output: 2, cacheRead: 50, requestCount: 1))

    let soFar = TokenComparison.sum(hourly: hourly, throughHour: 9)
    assertEqual(soFar.cacheRead, 100, "缺省小时按 0，只累加 0…9 时")
    assertEqual(soFar.requestCount, 5, "请求数按小时累加")
    let full = TokenComparison.sum(hourly: hourly, throughHour: 23)
    assertEqual(full.cacheRead, 150, "整日累加含 14 时")
    assertEqual(full.uncachedInput, 15, "未缓存输入累加")
    assertEqual(TokenComparison.sum(hourly: HarnessHourlyUsage.emptyDay()), HarnessTokenUsage.zero, "整日缺省为 0")
    assertEqual(TokenComparison.sum(hourly: hourly, throughHour: -1), HarnessTokenUsage.zero, "负小时上限返回 0")
    print("✅ Token 缺省小时与截至当前小时汇总 works")
}

private func testTokenEmptyState() {
    let empty = HarnessUsageSnapshot.empty(availability: .available(toolPath: "/usr/local/bin/zstd"),
                                           state: .idle)
    assertEqual(TokenComparison.isEmpty(empty), true, "空快照判空态")
    assertEqual(empty.totals.cacheHitRate, nil, "空态复用率为 nil 而非 0")

    let filled = HarnessUsageSnapshot(
        totals: HarnessUsageTotals(
            today: HarnessTokenUsage(uncachedInput: 1, output: 1, cacheRead: 1, requestCount: 1),
            thisWeek: .zero, allTime: HarnessTokenUsage(uncachedInput: 1, output: 1, cacheRead: 1, requestCount: 1),
            cacheHitRate: 0.5),
        daily: [HarnessDailyUsage(day: "2026-10-24", usage: HarnessTokenUsage(uncachedInput: 1, output: 1, cacheRead: 1))],
        projects: [], models: [], indexedSessions: 1, totalSessions: 1,
        lastScanAt: nil, indexingState: .ready,
        sourceAvailability: .available(toolPath: "/usr/local/bin/zstd"))
    assertEqual(TokenComparison.isEmpty(filled), false, "有数据不判空态")
    print("✅ Token 空态判据 works")
}

private func testTokenDelta() {
    assertEqual(TokenComparison.delta(today: 10, yesterday: 0), nil, "昨日为 0 不显示环比")
    assertEqual(TokenComparison.delta(today: 0, yesterday: 5)?.direction, .down, "今日为 0 视为下跌")
    assertEqual(TokenComparison.delta(today: 0, yesterday: 5)?.text, "↓ 100%", "下跌 100%")
    assertEqual(TokenComparison.delta(today: 135, yesterday: 100)?.text, "↑ 35%", "上涨百分比")
    assertEqual(TokenComparison.delta(today: 100, yesterday: 100)?.text, "↑ 0%", "持平算上涨 0%")
    assertEqual(TokenComparison.delta(today: 50, yesterday: 100)?.text, "↓ 50%", "下跌百分比")
    assertEqual(TokenComparison.delta(today: 1_240, yesterday: 100)?.text, "↑ 12.4×", "10 倍以上用倍数")
    assertEqual(TokenComparison.delta(today: 995, yesterday: 100)?.text, "↑ 895%", "不足 10 倍仍用百分比")
    assertEqual(TokenComparison.delta(today: 1_000, yesterday: 100)?.text, "↑ 10.0×", "满 10 倍切倍数")
    print("✅ Token 环比计算 works")
}

func runTokenPaneTests() {
    print("\n🧪 Testing Token 面板展示口径...")
    testTokenAbbreviated()
    testTokenRangeBoundary()
    testTokenMissingHour()
    testTokenEmptyState()
    testTokenDelta()
    print("✅ Token 面板展示口径 works")
}