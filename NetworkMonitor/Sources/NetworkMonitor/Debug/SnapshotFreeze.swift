#if DEBUG
import Foundation
import NetworkMonitorCore

// MARK: - 快照冻结（仅 DEBUG）

/// 快照冻结 —— 让 Token / 额度页的截图可做逐像素回归
///
/// 现状问题：同一份快照函数既出验收图、又做回归比对，而 Token 页里有实时数值与时钟，
/// 同一份代码连跑两次差异约 10%，逐像素比对永远收敛不了。
///
/// 解法：`NM_SNAPSHOT_FREEZE` 生效时（见 `SnapshotClock`），页面数据一律取本文件的
/// 固定 fixture，不读真实索引、不发网络请求；时钟走 `SnapshotClock.now`。
/// 不设环境变量时**一切照旧**（真实数据 + 真实时钟）。
enum SnapshotFreeze {

    /// 是否处于冻结模式
    static var isFrozen: Bool { SnapshotClock.isFrozen }

    // MARK: Token 页

    /// 冻结用 Token 快照：数值、日期、会话数全部固定
    ///
    /// 日期键按 `SnapshotClock.now` 推导，因此冻结时刻不同则日期标签不同，
    /// 但**同一冻结时刻**下每次运行拿到的快照完全一致。
    static func tokenSnapshot() -> HarnessUsageSnapshot {
        let now = SnapshotClock.now
        let dayKeys = (0..<30).map { offset in
            HarnessTokenTimeWindow.dayKey(for: now.addingTimeInterval(Double(-86_400 * (29 - offset))))
        }
        // 日用量：按固定序列（便于肉眼核对柱状图高低），今日为最后一天
        let dailyValues: [Int] = [
            12_400_000, 9_800_000, 15_600_000, 7_200_000, 18_900_000, 11_100_000, 6_400_000,
            13_700_000, 8_500_000, 16_200_000, 10_300_000, 5_900_000, 14_800_000, 9_100_000,
            17_500_000, 12_900_000, 7_700_000, 15_100_000, 8_900_000, 13_300_000, 10_800_000,
            6_100_000, 16_800_000, 11_500_000, 9_500_000, 14_200_000, 12_100_000, 8_300_000,
            15_900_000, 40_250_000,
        ]
        let daily = zip(dayKeys, dailyValues).map { key, total in
            HarnessDailyUsage(day: key, usage: usage(totalTokens: total, requests: max(1, total / 16_000)))
        }

        // 今日 / 昨日 24 小时桶：固定形状（上午一个峰、下午一个峰）
        let hourlyShape: [Double] = [
            0.02, 0.01, 0.01, 0.01, 0.02, 0.03, 0.06, 0.12, 0.18, 0.22, 0.16, 0.11,
            0.08, 0.14, 0.21, 0.27, 0.24, 0.19, 0.13, 0.09, 0.07, 0.05, 0.03, 0.02,
        ]
        let todayTotal = 40_250_000
        let yesterdayTotal = 33_800_000
        let todayHourly = hourlyShape.enumerated().map { hour, weight in
            HarnessHourlyUsage(hour: hour, usage: usage(totalTokens: Int(Double(todayTotal) * weight),
                                                        requests: max(1, Int(Double(todayTotal) * weight / 16_000))))
        }
        let yesterdayHourly = hourlyShape.enumerated().map { hour, weight in
            HarnessHourlyUsage(hour: hour, usage: usage(totalTokens: Int(Double(yesterdayTotal) * weight),
                                                        requests: max(1, Int(Double(yesterdayTotal) * weight / 16_000))))
        }

        let projects = [
            project("/Users/example/IdeaProjects/toolbar", "toolbar", 412, 21_800_000),
            project("/Users/example/IdeaProjects/norvels", "norvels", 208, 9_600_000),
            project("/Users/example/IdeaProjects/skills", "skills", 96, 4_300_000),
            project("/Users/example/IdeaProjects/dbx", "dbx", 41, 1_900_000),
            project("/Users/example/scratch", "scratch", 18, 850_000),
        ]
        let models = [
            model("deepseek", "deepseek-v4.1-flash", 6_400, 24_200_000),
            model("anthropic", "claude-sonnet-4.5", 980, 8_700_000),
            model("openai", "gpt-5-codex", 420, 3_900_000),
            model("deepseek", "deepseek-v4.1", 260, 1_650_000),
        ]

        let projectTotal = projects.reduce(HarnessTokenUsage()) { $0.adding($1.usage) }
        let modelTotal = models.reduce(HarnessTokenUsage()) { $0.adding($1.usage) }
        let todayUsage = todayHourly.compactMap(\.usage).reduce(HarnessTokenUsage()) { $0.adding($1) }
        let weekUsage = daily.suffix(7).reduce(HarnessTokenUsage()) { $0.adding($1.usage) }
        let allTimeUsage = daily.reduce(HarnessTokenUsage()) { $0.adding($1.usage) }

        var windowedProjects: [HarnessUsageWindow: [HarnessProjectUsage]] = [:]
        var windowedModels: [HarnessUsageWindow: [HarnessModelUsage]] = [:]
        var windowProjectTotals: [HarnessUsageWindow: HarnessTokenUsage] = [:]
        var windowModelTotals: [HarnessUsageWindow: HarnessTokenUsage] = [:]
        for window in HarnessUsageWindow.allCases {
            windowedProjects[window] = projects
            windowedModels[window] = models
            windowProjectTotals[window] = projectTotal
            windowModelTotals[window] = modelTotal
        }

        return HarnessUsageSnapshot(
            totals: HarnessUsageTotals(today: todayUsage, thisWeek: weekUsage,
                                       allTime: allTimeUsage, cacheHitRate: 0.986),
            daily: daily,
            todayHourly: todayHourly,
            yesterdayHourly: yesterdayHourly,
            projects: projects,
            models: models,
            windowedProjects: windowedProjects,
            windowedModels: windowedModels,
            windowProjectTotals: windowProjectTotals,
            windowModelTotals: windowModelTotals,
            indexedSessions: 1_964,
            totalSessions: 1_964,
            lastScanAt: now,
            indexingState: .ready,
            sourceAvailability: .available(toolPath: "/opt/homebrew/bin/zstd"))
    }

    // MARK: 内部

    /// 按总 token 拆成三段（缓存读占 98%，与生产量级一致）
    private static func usage(totalTokens: Int, requests: Int) -> HarnessTokenUsage {
        let cacheRead = Int(Double(totalTokens) * 0.98)
        let remaining = totalTokens - cacheRead
        let output = Int(Double(remaining) * 0.45)
        return HarnessTokenUsage(uncachedInput: remaining - output,
                                 output: output,
                                 cacheRead: cacheRead,
                                 cacheWrite: 0,
                                 requestCount: requests)
    }

    private static func project(_ path: String, _ name: String, _ sessions: Int, _ total: Int) -> HarnessProjectUsage {
        HarnessProjectUsage(path: path, displayName: name, sessionCount: sessions,
                            usage: usage(totalTokens: total, requests: max(1, total / 16_000)))
    }

    private static func model(_ provider: String, _ name: String, _ requests: Int, _ total: Int) -> HarnessModelUsage {
        HarnessModelUsage(provider: provider, model: name,
                          usage: usage(totalTokens: total, requests: requests))
    }
}
#endif
