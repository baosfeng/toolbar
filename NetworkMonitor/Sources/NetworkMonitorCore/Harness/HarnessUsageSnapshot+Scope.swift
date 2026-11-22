import Foundation

// MARK: - 单来源快照视图

/// 从全量快照裁出「单个来源」的同形快照
///
/// 冻结契约：Token 页切到单一来源时，Hero / 四族卡 / 趋势 / 缓存 / 排行都要等于
/// **该源自己的聚合**。聚合阶段已按 source 分桶算好（HarnessUsageSourceAggregation），
/// 这里只是按 TopN / 天数窗口裁剪一次，零查询 —— 切来源不会有任何 SQL。
extension HarnessUsageSnapshot {

    /// 按来源聚合（冻结契约）
    ///
    /// usage 取**累计**口径；未索引到的来源不出现。UI 不得据此推断「未安装」
    /// （没数据 ≠ 没装：目录存在但无会话、版本无遥测都会是「不出现」）。
    public var bySource: [TokenSourceID: HarnessSourceUsage] {
        perSourceAggregates.mapValues {
            HarnessSourceUsage(usage: $0.allTime, sessionCount: $0.indexedSessions)
        }
    }

    /// 该来源是否已索引到数据（bySource 里有键即「有数据」，与「已安装」无关）
    public func hasData(for source: TokenSourceID) -> Bool {
        perSourceAggregates[source] != nil
    }

    /// 裁成单来源的同形快照
    ///
    /// - 未索引到该来源：返回**空但同形**的快照（daily / hourly / windowed 都是空集合的空槽，
    ///   不是 nil、不缺字段），调用方不必到处判空；
    /// - availability / diagnostics：优先用该来源自己的口径，没登记过才回落全量；
    /// - indexingState / lastScanAt：跟全量一致（它们描述的是「索引这一轮」而不是某个来源）。
    public func scoped(to source: TokenSourceID) -> HarnessUsageSnapshot {
        let aggregate = perSourceAggregates[source] ?? .empty
        let daily = Array(aggregate.daily.suffix(HarnessUsageService.dailyLimit))
        let totals = HarnessUsageTotals(
            today: aggregate.today,
            thisWeek: aggregate.thisWeek,
            allTime: aggregate.allTime,
            cacheHitRate: HarnessCacheHitRate.compute(
                cacheRead: aggregate.allTime.cacheRead,
                uncachedInput: aggregate.allTime.uncachedInput
            )
        )
        var windowedProjects: [HarnessUsageWindow: [HarnessProjectUsage]] = [:]
        var windowedModels: [HarnessUsageWindow: [HarnessModelUsage]] = [:]
        var windowProjectTotals: [HarnessUsageWindow: HarnessTokenUsage] = [:]
        var windowModelTotals: [HarnessUsageWindow: HarnessTokenUsage] = [:]
        for item in aggregate.windowed {
            windowedProjects[item.window] = Array(item.projects.prefix(HarnessUsageService.projectLimit))
            windowedModels[item.window] = Array(item.models.prefix(HarnessUsageService.modelLimit))
            windowProjectTotals[item.window] = item.projectTotals
            windowModelTotals[item.window] = item.modelTotals
        }
        let availability = sourceAvailabilityBySource[source] ?? sourceAvailability
        return HarnessUsageSnapshot(
            totals: totals,
            daily: daily,
            todayHourly: aggregate.todayHourly,
            yesterdayHourly: aggregate.yesterdayHourly,
            projects: Array(aggregate.projects.prefix(HarnessUsageService.projectLimit)),
            models: Array(aggregate.models.prefix(HarnessUsageService.modelLimit)),
            windowedProjects: windowedProjects,
            windowedModels: windowedModels,
            windowProjectTotals: windowProjectTotals,
            windowModelTotals: windowModelTotals,
            indexedSessions: aggregate.indexedSessions,
            // 单来源的「发现到的文件数」不在聚合里（那是扫描器的一次性产物），
            // 这里退化为已索引会话数：对单源视图它正是「该源有多少会话」，
            // 且与全量口径的 max(totalSessions, indexedSessions) 取值方式一致。
            totalSessions: aggregate.indexedSessions,
            lastScanAt: lastScanAt,
            indexingState: indexingState,
            sourceAvailability: availability,
            sourceDiagnostics: sourceDiagnosticsBySource[source] ?? sourceDiagnostics,
            // 只保留该来源自己这一层：再嵌套下去没有消费者，白占内存
            perSourceAggregates: [source: aggregate],
            sourceAvailabilityBySource: [source: availability],
            sourceDiagnosticsBySource: sourceDiagnosticsBySource[source].map { [source: $0] } ?? [:]
        )
    }
}
