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

    print("\n🧪 Testing 窗口化聚合（真实 SQLite 内存库）...")
    testWindowedAggregationInDatabase()
    testWindowedAggregationPerformance()
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

// MARK: - 窗口化聚合（真实库）

/// 三档窗口的项目 / 模型聚合：数值、排序、占比分母、跨范围隔离
private func testWindowedAggregationInDatabase() {
    let db = DatabaseManager()
    db.initializeInMemory()
    let store: any HarnessTokenRepository = db

    // 今日 = 2026-11-06；造 4 天数据（今日 / 昨天 / 7 天内 / 30 天内 / 30 天外各一）
    let now = harnessDate(2026, 11, 6, 20)
    let events: [(day: Int, project: String, model: String, tokens: Int)] = [
        (0, "/Users/me/IdeaProjects/alpha", "deepseek-v4", 1_000),
        (0, "/Users/me/IdeaProjects/beta", "gpt-5", 500),
        (1, "/Users/me/IdeaProjects/alpha", "deepseek-v4", 2_000),
        (5, "/Users/me/IdeaProjects/gamma", "deepseek-v4", 3_000),
        (20, "/Users/me/IdeaProjects/alpha", "deepseek-v4", 4_000),
        (40, "/Users/me/IdeaProjects/alpha", "deepseek-v4", 9_000),   // 30 天外，任何窗口都不该出现
    ]
    for (index, item) in events.enumerated() {
        let date = now.addingTimeInterval(-Double(item.day) * 86_400)
        let tsMs = Int64((date.timeIntervalSince1970 * 1000).rounded())
        let record = HarnessSessionScanRecord(path: "/stub/\(index)", sessionID: "s\(index)",
                                              size: 1, mtimeMs: 1, scannedAt: 0)
        _ = store.harnessReplaceSession(record: record, events: [
            makeEvent(sessionID: "s\(index)", cwd: item.project, model: item.model, tsMs: tsMs,
                      usage: HarnessTokenUsage(uncachedInput: item.tokens, requestCount: 1)),
        ], cwd: item.project)
    }

    let aggregate = store.harnessAggregate(now: now)
    let today = aggregate.windowed.first { $0.window == .today }
    let d7 = aggregate.windowed.first { $0.window == .last7Days }
    let d30 = aggregate.windowed.first { $0.window == .last30Days }
    assertNotNil(today, "今日窗口存在")
    assertNotNil(d7, "7 天窗口存在")
    assertNotNil(d30, "30 天窗口存在")

    // 今日：alpha 1000 + beta 500
    assertEqual(today?.projects.count, 2, "今日 2 个项目")
    assertEqual(today?.projects.first?.path.hasSuffix("alpha") ?? false, true, "今日榜首 alpha")
    assertEqual(today?.projects.first?.usage.totalTokens, 1_000, "今日 alpha 1000 tok")
    assertEqual(today?.projectTotals.totalTokens, 1_500, "今日项目合计 = 全部项目（alpha+beta）")
    assertEqual(today?.models.count, 2, "今日 2 个模型")

    // 7 天（今日往前 6 天，含昨天与第 5 天）：alpha 3000 + beta 500 + gamma 3000
    assertEqual(d7?.projects.count, 3, "7 天 3 个项目")
    assertEqual(d7?.projectTotals.totalTokens, 6_500, "7 天项目合计")
    assertEqual(d7?.projects.first?.usage.totalTokens, 3_000, "7 天榜首并列时取较小者（alpha/gamma）")
    assertEqual(d7?.projects.first?.path.hasSuffix("alpha") ?? false, true, "并列按路径升序，alpha 在前")
    assertEqual(d7?.models.count, 2, "7 天 2 个模型")

    // 30 天（含第 20 天，不含第 40 天）：alpha 7000 + beta 500 + gamma 3000
    assertEqual(d30?.projects.count, 3, "30 天 3 个项目（30 天外的第 40 天不出现）")
    assertEqual(d30?.projectTotals.totalTokens, 10_500, "30 天项目合计（排除 9000 的窗口外事件）")

    // 一致性：项目合计 ≤ 该窗口 Hero 总量（Hero 口径 = 全部事件，含无法归属项目的事件）
    assertEqual((today?.projectTotals.totalTokens ?? 0) <= aggregate.today.totalTokens, true,
                "今日 sum(项目) ≤ Hero 总量")
    assertEqual((d30?.projectTotals.totalTokens ?? 0) <= aggregate.allTime.totalTokens, true,
                "30 天 sum(项目) ≤ 累计总量")

    // 三档互不串数据：今日项目合计 < 7 天 < 30 天
    assertEqual((today?.projectTotals.totalTokens ?? 0) < (d7?.projectTotals.totalTokens ?? 0), true,
                "今日合计 < 7 天合计（不串数据）")
    assertEqual((d7?.projectTotals.totalTokens ?? 0) < (d30?.projectTotals.totalTokens ?? 0), true,
                "7 天合计 < 30 天合计")
}

/// 记录一次窗口化聚合耗时（回归护栏：库 133k 行时实测约 186ms，此后显著变慢要能看见）
private func testWindowedAggregationPerformance() {
    let db = DatabaseManager()
    db.initializeInMemory()
    let store: any HarnessTokenRepository = db
    let now = harnessDate(2026, 11, 6, 20)
    // 造 2000 条事件（20 个项目 / 8 个模型 / 30 天）
    for index in 0..<2_000 {
        let tsMs = harnessTs(2026, 11, 6) - Int64(index % 30) * 86_400_000
        let record = HarnessSessionScanRecord(path: "/stub/p\(index)", sessionID: "perf\(index)",
                                              size: 1, mtimeMs: 1, scannedAt: 0)
        _ = store.harnessReplaceSession(record: record, events: [
            makeEvent(sessionID: "perf\(index)", cwd: "/Users/me/proj\(index % 20)",
                      model: "model\(index % 8)", tsMs: tsMs,
                      usage: HarnessTokenUsage(uncachedInput: 100, requestCount: 1)),
        ], cwd: "/Users/me/proj\(index % 20)")
    }
    let start = Date()
    let aggregate = store.harnessAggregate(now: now)
    let elapsed = Date().timeIntervalSince(start)
    assertEqual(aggregate.windowed.count, 3, "一次聚合产出三档窗口")
    assertEqual(elapsed < 3.0, true, "2000 条事件的聚合在 3 秒内完成（实测 \(String(format: "%.1f", elapsed * 1000)) ms）")
    print("   ⏱ 2000 事件 × 三档窗口化聚合：\(String(format: "%.1f", elapsed * 1000)) ms")
}

