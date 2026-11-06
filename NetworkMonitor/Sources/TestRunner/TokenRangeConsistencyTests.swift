import Foundation
import NetworkMonitorCore

// MARK: - Token 页「按项目 / 按模型」随范围口径一致性测试

/// 用户反馈「上面的数据和下面的数据对不上」（Hero 340M vs 按项目 7.13B）——
/// 根因是这两块曾用累计口径。本套件锁死三条契约：
/// 1. 同范围下 sum(项目 token) ≤ Hero 总量；
/// 2. 三档窗口各算各的，跨范围不串数据；
/// 3. 占比分母是该窗口内全部项目的合计（不是 TopN 行求和）。
func runTokenRangeConsistencyTests() {
    print("\n🧪 Testing Token 范围口径一致性（项目/模型 vs Hero）...")
    testRangeWindowBoundaries()
    testProjectModelFollowRange()
    testShareDenominator()
}

// MARK: - 窗口边界

private func testRangeWindowBoundaries() {
    let calendar = HarnessTokenTimeWindow.calendar
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let todayStart = HarnessTokenTimeWindow.startOfDayMs(now: now)
    let dayMs = HarnessTokenTimeWindow.millisecondsPerDay

    let today = HarnessRangeWindows.window(.today, now: now)
    assertEqual(today.fromMs, todayStart, "今日窗口从 00:00 起（与 Hero / 24 桶同源）")
    assertEqual(today.toMs, todayStart + dayMs, "今日窗口到次日 00:00 止（不含）")

    let d7 = HarnessRangeWindows.window(.last7Days, now: now)
    assertEqual(d7.toMs, today.toMs, "7 天窗口与今日同终点")
    assertEqual(d7.fromMs, todayStart - 6 * dayMs, "7 天窗口含今日往前 6 天，共 7 天")
    assertEqual(HarnessUsageWindow.last7Days.days, 7, "窗口天数 7")

    let d30 = HarnessRangeWindows.window(.last30Days, now: now)
    assertEqual(d30.fromMs, todayStart - 29 * dayMs, "30 天窗口含今日往前 29 天")
    assertEqual(HarnessUsageWindow.last30Days.days, 30, "窗口天数 30")

    // 嵌套关系：今日 ⊂ 7 天 ⊂ 30 天 —— 口径不嵌套就说明边界算法错了
    assertEqual(d7.contains(tsMs: today.fromMs + 1), true, "今日起点落在 7 天窗口内")
    assertEqual(d30.contains(tsMs: d7.fromMs), true, "7 天起点落在 30 天窗口内")
    assertEqual(today.contains(tsMs: d7.fromMs), false, "7 天起点不在今日窗口内")
    assertEqual(today.contains(tsMs: today.toMs), false, "右端不含（避免跨日重复计数）")

    assertEqual(HarnessRangeWindows.allWindows(now: now).map(\.window),
                HarnessUsageWindow.allCases, "批量窗口顺序与 allCases 一致")
    assertEqual(HarnessUsageWindow.allCases.map(\.title), ["今日", "近 7 天", "近 30 天"],
                "卡头文案前缀")
    // 展示层范围 → 数据层窗口的映射（Hero 与项目/模型必须映射到同一窗口）
    assertEqual(TokenRange.today.window, .today, "今日 → 今日窗口")
    assertEqual(TokenRange.d7.window, .last7Days, "近 7 天 → 7 天窗口")
    assertEqual(TokenRange.d30.window, .last30Days, "近 30 天 → 30 天窗口")
    _ = calendar
}

// MARK: - 项目 / 模型随范围

private func testProjectModelFollowRange() {
    let small = HarnessProjectUsage(path: "/tmp/a", displayName: "a", sessionCount: 1,
                                    usage: HarnessTokenUsage(uncachedInput: 1_000, requestCount: 1))
    let big = HarnessProjectUsage(path: "/tmp/b", displayName: "b", sessionCount: 2,
                                  usage: HarnessTokenUsage(uncachedInput: 9_000, cacheRead: 90_000,
                                                           requestCount: 2))
    let model = HarnessModelUsage(provider: "deepseek", model: "v4",
                                  usage: HarnessTokenUsage(uncachedInput: 6_000, requestCount: 1))

    // 今日：只有 a（1000 tok）；7 天：a + b；30 天：多一个 c
    let snapshot = HarnessUsageSnapshot(
        totals: HarnessUsageTotals(today: .zero, thisWeek: .zero, allTime: .zero, cacheHitRate: nil),
        daily: [],
        projects: [big, small],
        models: [model],
        windowedProjects: [
            .today: [small],
            .last7Days: [big, small],
            .last30Days: [big, small],
        ],
        windowedModels: [
            .today: [model],
            .last7Days: [model],
            .last30Days: [model],
        ],
        windowProjectTotals: [.today: small.usage, .last7Days: .init(uncachedInput: 10_000),
                              .last30Days: .init(uncachedInput: 10_000)],
        windowModelTotals: [.today: model.usage, .last7Days: model.usage, .last30Days: model.usage],
        indexedSessions: 3, totalSessions: 3, lastScanAt: nil,
        indexingState: .ready, sourceAvailability: .available(toolPath: "/usr/local/bin/zstd"))

    assertEqual(TokenDerive.projectRows(snapshot, window: .today).count, 1, "今日只有 1 个项目")
    assertEqual(TokenDerive.projectRows(snapshot, window: .last7Days).count, 2, "7 天有 2 个项目")
    assertEqual(TokenDerive.projectRows(snapshot, window: .last7Days).first?.name, "b",
                "7 天按 token 降序，b 在首位")
    assertEqual(TokenDerive.projectRows(snapshot, window: .today).first?.name, "a",
                "今日只有 a（跨范围不串数据）")

    // TokenPaneModel 的卡头与行数随范围
    for range in [TokenRange.today, .d7, .d30] {
        let model = TokenPaneModel.make(snapshot: snapshot, range: range, hourScope: .today,
                                        hourView: .stack, metric: .total, trendMode: .stack)
        assertEqual(model.projectMeta, "\(range.window.title) \(model.projects.count) 个",
                    "\(range.window.title) 卡头文案随范围")
        assertEqual(model.projectCount, model.projects.count, "projectCount 与行数一致")
        assertEqual(model.modelMeta, "\(range.window.title) \(model.models.count) 个",
                    "\(range.window.title) 模型卡头随范围")
    }
}

// MARK: - 占比分母

private func testShareDenominator() {
    // 分母含 TopN 之外的项目：TopN 行占比之和 < 100%，但每行占比按窗口总量算
    let top = HarnessProjectUsage(path: "/tmp/top", displayName: "top", sessionCount: 1,
                                  usage: HarnessTokenUsage(uncachedInput: 300, requestCount: 1))
    let snapshot = tokenSnapshot(projects: [top],
                                 window: .today,
                                 windowProjectTotals: HarnessTokenUsage(uncachedInput: 400))
    let rows = TokenDerive.projectRows(snapshot, window: .today)
    assertEqual(rows.first?.share, 0.75, "占比 = 该行 / 窗口全部项目合计（300/400）")
    assertEqual(rows.reduce(0.0) { $0 + $1.share } < 1, true,
                "TopN 之外还有项目时占比之和 < 100%（不虚高）")

    // 模型同理
    let model = HarnessModelUsage(provider: "p", model: "m",
                                  usage: HarnessTokenUsage(uncachedInput: 200, requestCount: 1))
    let modelSnapshot = tokenSnapshot(models: [model], window: .today,
                                      windowModelTotals: HarnessTokenUsage(uncachedInput: 800))
    let modelRows = TokenDerive.modelRows(modelSnapshot, window: .today)
    assertEqual(modelRows.first?.share, 0.25, "模型占比 = 该行 / 窗口全部模型合计")

    // 分母为 0（窗口内无数据）时不崩，占比为 0
    let emptySnapshot = tokenSnapshot(window: .today, windowProjectTotals: .zero)
    assertEqual(TokenDerive.projectRows(emptySnapshot, window: .today).isEmpty, true,
                "窗口无数据时项目行为空（不编造行）")

    // 跨范围：取不到该窗口聚合时返回空行，而不是退回累计（否则又会出现 20~30 倍落差）
    let missingWindow = tokenSnapshot(projects: [top], window: .last7Days)
    assertEqual(TokenDerive.projectRows(missingWindow, window: .today).isEmpty, true,
                "窗口缺数据时为空，不回落到别的窗口")
}
