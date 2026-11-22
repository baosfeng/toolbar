import Foundation

// MARK: - 快照构建与按需重算

/// HarnessUsageService 的快照侧 — 从主文件拆出（主文件贴近单文件 15 KiB 上限）
///
/// 分工：主文件负责「索引怎么跑」，本文件负责「聚合何时算、快照怎么裁剪、事件何时发」。
/// 聚合是这里唯一的重活：一次 `harnessAggregate` 是 8~10 条全表查询（单次 0.2–1.0 s），
/// 因此只在两个时机算 ——（a）一轮索引结束、（b）有写入未计入快照时按需补算（Token 页可见）。
/// 无变更的重复刷新（开面板、切页、点击）走缓存快照，零查询。
extension HarnessUsageService {

    // MARK: - 快照构建

    /// 从落库数据构建快照（并写入内存缓存 + 发事件）
    ///
    /// - Parameter force: 强制重算。false 时仅在「有写入未计入 / 还没有缓存」时算一次：
    ///   无变更的重复刷新（开面板 / 切 Token 页）因此是零聚合，不再每次发布都跑
    ///   8~10 条全表查询（单次 0.2–1.0 s，正是把数据库队列与主线程一起拖住的那一段）
    func publishSnapshot(availability: HarnessSourceAvailability, totalSessions: Int,
                         now: Date, force: Bool) {
        lock.lock()
        let needsAggregate = force || snapshotStale
        lock.unlock()
        guard needsAggregate else { return }
        let aggregate = store.harnessAggregate(now: now)
        let snapshot = makeSnapshot(
            from: aggregate,
            availability: availability,
            totalSessions: totalSessions,
            lastScanAt: now
        )
        lock.lock()
        cachedSnapshot = snapshot
        snapshotStale = false
        lock.unlock()
        AppEvents.postHarnessUsageChanged()
    }

    /// 冷启动预热：内存无缓存时先读一次落库数据（不发事件，避免开面板时多余刷新）
    func seedSnapshotIfNeeded(availability: HarnessSourceAvailability) {
        lock.lock()
        let hasCache = cachedSnapshot != nil
        lock.unlock()
        guard !hasCache else { return }
        let aggregate = store.harnessAggregate(now: nowProvider())
        guard aggregate.indexedSessions > 0 else { return }
        let snapshot = makeSnapshot(
            from: aggregate,
            availability: availability,
            totalSessions: aggregate.indexedSessions,
            lastScanAt: nil
        )
        lock.lock()
        cachedSnapshot = snapshot
        snapshotStale = false
        lock.unlock()
    }

    /// 标记「快照落后于已提交写入」：下一次发布 / 按需重算必须重跑聚合
    func markSnapshotStale() {
        lock.lock()
        snapshotStale = true
        lock.unlock()
    }

    // MARK: - 按需重算

    /// 有未计入快照的写入时重算一次（Token 页可见 / 切换范围时调用）
    ///
    /// 不阻塞调用线程：排在索引队列上，索引进行中会自动落到索引结束之后（不会把半轮写入
    /// 的中间态推给界面）；无脏数据即零查询。范围切换读到的是快照里已算好的三档窗口，不再查库。
    public func refreshSnapshotIfDirty() {
        lock.lock()
        let shouldSchedule = snapshotStale && !snapshotRefreshQueued
        if shouldSchedule { snapshotRefreshQueued = true }
        lock.unlock()
        guard shouldSchedule else { return }
        queue.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.snapshotRefreshQueued = false
            self.lock.unlock()
            self.recomputeSnapshotIfStale()
        }
    }

    private func recomputeSnapshotIfStale() {
        lock.lock()
        let stale = snapshotStale
        lock.unlock()
        guard stale else { return }
        publishSnapshot(availability: scanner.availability,
                        totalSessions: snapshot().totalSessions,
                        now: nowProvider(),
                        force: true)
    }

    /// 由聚合结果裁剪出对外快照（TopN 与 33 天窗口在这里收敛）
    private func makeSnapshot(
        from aggregate: HarnessAggregate,
        availability: HarnessSourceAvailability,
        totalSessions: Int,
        lastScanAt: Date?
    ) -> HarnessUsageSnapshot {
        // 趋势只保留最近 dailyLimit 天；无数据的日子不补 0，保持空缺
        let daily = Array(aggregate.daily.suffix(Self.dailyLimit))
        let totals = HarnessUsageTotals(
            today: aggregate.today,
            thisWeek: aggregate.thisWeek,
            allTime: aggregate.allTime,
            cacheHitRate: HarnessCacheHitRate.compute(
                cacheRead: aggregate.allTime.cacheRead,
                uncachedInput: aggregate.allTime.uncachedInput
            )
        )
        // 按范围聚合在同一次查询里算好，这里按 TopN 裁剪后按窗口分发
        var windowedProjects: [HarnessUsageWindow: [HarnessProjectUsage]] = [:]
        var windowedModels: [HarnessUsageWindow: [HarnessModelUsage]] = [:]
        var windowProjectTotals: [HarnessUsageWindow: HarnessTokenUsage] = [:]
        var windowModelTotals: [HarnessUsageWindow: HarnessTokenUsage] = [:]
        for item in aggregate.windowed {
            windowedProjects[item.window] = Array(item.projects.prefix(Self.projectLimit))
            windowedModels[item.window] = Array(item.models.prefix(Self.modelLimit))
            windowProjectTotals[item.window] = item.projectTotals
            windowModelTotals[item.window] = item.modelTotals
        }
        // 单来源口径的可用性与诊断：只登记已实现来源（未实现的源没有目录可诊断，
        // 它们的 status 由设置页按 hasIndexer 自己说明「未实现」）
        var availabilityBySource: [TokenSourceID: HarnessSourceAvailability] = [:]
        var diagnosticsBySource: [TokenSourceID: HarnessSourceDiagnostics] = [:]
        for source in TokenSourceID.allCases where source.hasIndexer {
            let sourceAvailability = scanner.availability(for: source)
            availabilityBySource[source] = sourceAvailability
            diagnosticsBySource[source] = scanner.diagnostics(for: source)
        }
        return HarnessUsageSnapshot(
            totals: totals,
            daily: daily,
            todayHourly: aggregate.todayHourly,
            yesterdayHourly: aggregate.yesterdayHourly,
            projects: Array(aggregate.projects.prefix(Self.projectLimit)),
            models: Array(aggregate.models.prefix(Self.modelLimit)),
            windowedProjects: windowedProjects,
            windowedModels: windowedModels,
            windowProjectTotals: windowProjectTotals,
            windowModelTotals: windowModelTotals,
            indexedSessions: aggregate.indexedSessions,
            totalSessions: max(totalSessions, aggregate.indexedSessions),
            lastScanAt: lastScanAt,
            indexingState: state,
            sourceAvailability: availability,
            sourceDiagnostics: HarnessSourceDiagnostics.make(resolution: scanner.sourceResolution,
                                                             availability: availability),
            perSourceAggregates: aggregate.bySource,
            sourceAvailabilityBySource: availabilityBySource,
            sourceDiagnosticsBySource: diagnosticsBySource
        )
    }
}
