import Foundation
import NetworkMonitorCore

// MARK: - 来源收窄与单源视图（设计规格 §3 / §6）
//
// 覆盖：单源 → 用该源 / 双源 → 「全部」/ 零源 → 「全部」/ bySource 为空的老快照按 legacy 单源算 /
// scoped(to:) 各源之和 == 全量 / 未索引来源返回空但同形 / HarnessRebuildScope.source 的显示名与拆解。
// fixture 全在内存里自造：不读数据库、不读真实目录。

// MARK: - 构造辅助

private func aggregate(uncached: Int, output: Int, cacheRead: Int, sessions: Int,
                       day: String = "2026-01-05",
                       windowed: [HarnessWindowedUsage] = []) -> HarnessSourceAggregate {
    let usage = HarnessTokenUsage(uncachedInput: uncached, output: output,
                                  cacheRead: cacheRead, cacheWrite: 0,
                                  requestCount: sessions)
    return HarnessSourceAggregate(
        allTime: usage, today: usage, thisWeek: usage,
        daily: sessions > 0 ? [HarnessDailyUsage(day: day, usage: usage)] : [],
        projects: sessions > 0 ? [HarnessProjectUsage(path: "/tmp/" + day, displayName: day,
                                                      sessionCount: sessions, usage: usage)] : [],
        models: sessions > 0 ? [HarnessModelUsage(provider: "p", model: "m", usage: usage)] : [],
        windowed: windowed,
        indexedSessions: sessions
    )
}

/// 全量口径 = 各来源之和（与聚合层的口径一致）
private func snapshot(bySource: [TokenSourceID: HarnessSourceAggregate],
                      availability: HarnessSourceAvailability = .available(toolPath: ""),
                      availabilityBySource: [TokenSourceID: HarnessSourceAvailability] = [:],
                      state: HarnessIndexingState = .ready) -> HarnessUsageSnapshot {
    let all = bySource.values.reduce(HarnessTokenUsage.zero) { $0.adding($1.allTime) }
    let sessions = bySource.values.reduce(0) { $0 + $1.indexedSessions }
    return HarnessUsageSnapshot(
        totals: HarnessUsageTotals(today: all, thisWeek: all, allTime: all, cacheHitRate: nil),
        daily: [], projects: [], models: [],
        indexedSessions: sessions, totalSessions: sessions, lastScanAt: nil,
        indexingState: state, sourceAvailability: availability,
        perSourceAggregates: bySource,
        sourceAvailabilityBySource: availabilityBySource
    )
}

// MARK: - 套件

func runTokenSourceScopeTests() {
    print("🧪 Testing 来源收窄（页名判据 / scoped 同形 / 重建范围）...")

    let claude = aggregate(uncached: 1000, output: 500, cacheRead: 2000, sessions: 3)
    let codex = aggregate(uncached: 700, output: 100, cacheRead: 200, sessions: 2,
                          day: "2026-01-06")
    let twoSources = snapshot(bySource: [.claudeCode: claude, .codex: codex])
    let oneSource = snapshot(bySource: [.claudeCode: claude])

    // 单源 → 页名写该源
    assertEqual(TokenSourceScope.dataSources(in: oneSource), [TokenSourceID.claudeCode], "单源：有数据来源清单")
    assertEqual(TokenSourceScope.displaySource(selected: nil,
                                               dataSources: TokenSourceScope.dataSources(in: oneSource)),
                TokenSourceID.claudeCode, "单源：页名用该来源")

    // 双源 → 页名写「全部」（nil）
    assertEqual(TokenSourceScope.dataSources(in: twoSources),
                [TokenSourceID.claudeCode, TokenSourceID.codex], "双源：按 allCases 顺序列出")
    assertEqual(TokenSourceScope.displaySource(selected: nil,
                                               dataSources: TokenSourceScope.dataSources(in: twoSources)),
                nil as TokenSourceID?, "双源：页名为「全部」")
    assertEqual(TokenSourceScope.displaySource(selected: .codex,
                                               dataSources: TokenSourceScope.dataSources(in: twoSources)),
                TokenSourceID.codex, "双源：显式选中优先")

    // 零源：显式空清单 → 「全部」
    assertEqual(TokenSourceScope.displaySource(selected: nil, dataSources: []),
                nil as TokenSourceID?, "零源：页名为「全部」")

    // 老快照（bySource 为空）→ 按 legacy 单源算，页名写 DSH 而不是「全部」
    let legacy = snapshot(bySource: [:])
    assertEqual(legacy.bySource.isEmpty, true, "老快照：bySource 为空")
    assertEqual(TokenSourceScope.dataSources(in: legacy), [TokenSourceID.legacy], "老快照：按 DSH 单源算")
    assertEqual(TokenSourceScope.displaySource(selected: nil,
                                               dataSources: TokenSourceScope.dataSources(in: legacy)),
                TokenSourceID.dsh, "老快照：页名写 DSH")

    // bySource 非空但每条都空（0 会话 + 零用量）→ 不算「有数据」
    let emptyEntries = snapshot(bySource: [
        .claudeCode: aggregate(uncached: 0, output: 0, cacheRead: 0, sessions: 0),
        .codex: aggregate(uncached: 0, output: 0, cacheRead: 0, sessions: 0),
    ])
    assertEqual(TokenSourceScope.dataSources(in: emptyEntries), [], "空条目：不算有数据")
    assertEqual(TokenSourceScope.displaySource(selected: nil, dataSources: []),
                nil as TokenSourceID?, "空条目：页名为「全部」")

    // MARK: narrow —— 切来源是纯裁剪，不做任何合并
    assertEqual(TokenSourceScope.narrow(twoSources, to: nil), twoSources, "narrow(nil)：原样返回跨源合计")
    assertEqual(TokenSourceScope.narrow(twoSources, to: .claudeCode),
                twoSources.scoped(to: .claudeCode), "narrow(源)：等价于 scoped(to:)")

    // MARK: scoped(to:) —— 与全量同形，且各源之和 == 全量
    let windowTotals = HarnessTokenUsage(uncachedInput: 1000, output: 500,
                                         cacheRead: 2000, cacheWrite: 0, requestCount: 3)
    let claudeWithWindows = aggregate(uncached: 1000, output: 500, cacheRead: 2000, sessions: 3,
                                      windowed: [HarnessWindowedUsage(window: .today,
                                                                      projects: [], models: [],
                                                                      projectTotals: windowTotals,
                                                                      modelTotals: windowTotals)])
    let full = snapshot(bySource: [.claudeCode: claudeWithWindows, .codex: codex],
                        availabilityBySource: [.claudeCode: .available(toolPath: ""),
                                               .codex: .sessionsDirectoryMissing(path: "/tmp/none")])
    let scopedClaude = full.scoped(to: .claudeCode)
    let scopedCodex = full.scoped(to: .codex)

    assertEqual(scopedClaude.totals.allTime, claudeWithWindows.allTime, "scoped：单源累计")
    assertEqual(scopedClaude.indexedSessions, 3, "scoped：单源会话数")
    assertEqual(scopedClaude.totalSessions, 3, "scoped：单源发现文件数退化为会话数")
    assertEqual(scopedClaude.daily.map(\.day), ["2026-01-05"], "scoped：只留该源的天桶")
    assertEqual(scopedClaude.windowProjectTotals[.today], windowTotals, "scoped：窗口分母随之收窄")
    assertEqual(scopedClaude.sourceAvailability, .available(toolPath: ""), "scoped：用该源自己的可用性")
    assertEqual(scopedCodex.sourceAvailability, .sessionsDirectoryMissing(path: "/tmp/none"),
                "scoped：Codex 用自己的可用性")
    assertEqual(scopedClaude.todayHourly.count, 24, "scoped：小时桶仍是 24 槽")
    assertEqual(scopedClaude.yesterdayHourly.count, 24, "scoped：昨日小时桶仍是 24 槽")

    let sum = scopedClaude.totals.allTime.adding(scopedCodex.totals.allTime)
    assertEqual(sum, full.totals.allTime, "scoped：各源之和 == 全量累计")
    assertEqual(scopedClaude.indexedSessions + scopedCodex.indexedSessions, full.indexedSessions,
                "scoped：各源会话数之和 == 全量")
    assertEqual(full.bySource[.claudeCode]?.usage.totalTokens, claudeWithWindows.allTime.totalTokens,
                "bySource：键值取该源累计用量（不是全量）")

    // 未索引到的来源：空但同形，不缺字段、不崩
    let orphan = full.scoped(to: .gemini)
    assertEqual(orphan.totals.allTime, HarnessTokenUsage.zero, "未索引：累计为空")
    assertEqual(orphan.daily.count, 0, "未索引：天桶为空")
    assertEqual(orphan.projects.count, 0, "未索引：项目为空")
    assertEqual(orphan.models.count, 0, "未索引：模型为空")
    assertEqual(orphan.todayHourly.count, 24, "未索引：今日小时桶仍 24 槽")
    assertEqual(orphan.indexedSessions, 0, "未索引：会话数为 0")
    assertEqual(orphan.sourceAvailability, full.sourceAvailability, "未索引：可用性回落全量")
    assertEqual(Array(orphan.perSourceAggregates.keys), [TokenSourceID.gemini], "未索引：只保留该源一层")

    // MARK: HarnessRebuildScope.source —— 显示名与两维拆解
    assertEqual(HarnessRebuildScope.source(.claudeCode, .full).displayName,
                "Claude Code · 全部历史数据", "重建范围：单源全量显示名")
    assertEqual(HarnessRebuildScope.source(.codex, .sinceDays(3)).displayName,
                "Codex · 最近 3 天的会话数据", "重建范围：单源按天显示名")
    assertEqual(HarnessRebuildScope.source(.dsh, .sinceDays(0)).displayName,
                "DSH · 最近 1 天的会话数据", "重建范围：天数下限夹到 1")

    let decomposed = HarnessRebuildScope.source(.claudeCode, .sinceDays(7)).decomposed()
    assertEqual(decomposed.source, TokenSourceID.claudeCode, "decomposed：来源维")
    assertEqual(decomposed.base, HarnessRebuildScope.sinceDays(7), "decomposed：时间维")
    let plain = HarnessRebuildScope.full.decomposed()
    assertEqual(plain.source, nil as TokenSourceID?, "decomposed：全量为无来源")
    assertEqual(plain.base, HarnessRebuildScope.full, "decomposed：全量时间维")
    assertEqual(HarnessRebuildScope.source(.claudeCode, .source(.codex, .full)).decomposed().base,
                HarnessRebuildScope.full, "decomposed：嵌套时外层来源优先")
    assertEqual(HarnessRebuildScope.source(.claudeCode, .source(.codex, .full)).decomposed().source,
                TokenSourceID.claudeCode, "decomposed：嵌套取最外层来源")

    // 合并：同源取更广，跨源退化为全量（宁可多清，不能谎报来源）
    assertEqual(HarnessRebuildScope.merge(.source(.claudeCode, .sinceDays(3)),
                                          .source(.claudeCode, .sinceDays(7))),
                HarnessRebuildScope.source(.claudeCode, .sinceDays(7)), "merge：同源取更广")
    assertEqual(HarnessRebuildScope.merge(.source(.claudeCode, .full), .source(.codex, .full)),
                HarnessRebuildScope.full, "merge：跨源退化为全量")
    assertEqual(HarnessRebuildScope.merge(nil, .sinceDays(2)),
                HarnessRebuildScope.sinceDays(2), "merge：nil 与有值取有值")
    assertEqual(HarnessRebuildScope.merge(nil, nil), nil as HarnessRebuildScope?, "merge：双 nil 得 nil")

    print("✅ 来源收窄与重建范围 works")
}
