import Foundation
import SQLite3

// MARK: - 按来源的聚合（一条查询出全部来源的分桶）

/// 单来源快照的数据来源
///
/// **性能口径（P0）**：这里是「每轮聚合多出多少开销」的关键路径。合并后只剩 5 条查询：
/// 1. 按 (source, 天) 聚合 —— 顺带用日桶推导累计 / 今日 / 本周三个总数；
/// 2. 按 (source, 小时) 一条查询同时出今日与昨日 24 槽（CASE 分桶）；
/// 3. 项目（累计 + 三档窗口同一条，见 HarnessUsageSourceRanking）；
/// 4. 模型（同上）；
/// 5. 按来源的会话数（表很小）。
/// 改前是 9 条（其中 8 条扫事件表），合并后事件表只扫 4 遍，口径与「全部」共用同一套边界。
///
/// - Warning: 不得在 query(sql:handler:) 的回调内调用本扩展方法，否则死锁。
extension DatabaseManager {

    /// 全部来源的聚合（键缺失 = 该来源未索引到）
    func harnessSourceAggregates(_ db: OpaquePointer, now: Date) -> [TokenSourceID: HarnessSourceAggregate] {
        let daily = harnessSourceDaily(db)
        let hourly = harnessSourceHourly(db, now: now)
        let sessions = harnessSourceSessionCounts(db)
        let rankings = harnessSourceRankings(db, now: now)

        var sources = Set(daily.keys)
        sources.formUnion(hourly.today.keys)
        sources.formUnion(hourly.yesterday.keys)
        sources.formUnion(sessions.keys)
        sources.formUnion(rankings.projects.keys)
        sources.formUnion(rankings.models.keys)
        sources.formUnion(rankings.windowed.keys)

        var result: [TokenSourceID: HarnessSourceAggregate] = [:]
        for source in sources {
            let buckets = daily[source] ?? []
            let totals = Self.sourceTotals(from: buckets, now: now)
            result[source] = HarnessSourceAggregate(
                allTime: totals.allTime,
                today: totals.today,
                thisWeek: totals.thisWeek,
                daily: buckets,
                projects: rankings.projects[source] ?? [],
                models: rankings.models[source] ?? [],
                windowed: HarnessUsageWindow.allCases.map { window in
                    rankings.windowed[source]?[window] ?? HarnessWindowedUsage.empty(window)
                },
                todayHourly: hourly.today[source] ?? HarnessHourlyUsage.emptyDay(),
                yesterdayHourly: hourly.yesterday[source] ?? HarnessHourlyUsage.emptyDay(),
                indexedSessions: sessions[source] ?? 0
            )
        }
        return result
    }

    /// 由日桶推导累计 / 今日 / 本周（纯函数：同一批行、同一套上海自然日边界）
    ///
    /// 与既有全量口径等价：累计 = 全部日桶之和；今日 = 今日那个桶；本周 = 本周一（含）之后的桶。
    /// 这样就不必为「三个总数」再扫一遍事件表（改前那是最贵的一条之一）。
    static func sourceTotals(
        from buckets: [HarnessDailyUsage],
        now: Date
    ) -> (allTime: HarnessTokenUsage, today: HarnessTokenUsage, thisWeek: HarnessTokenUsage) {
        let todayKey = HarnessTokenTimeWindow.dayKey(for: now)
        let weekStartMs = HarnessTokenTimeWindow.startOfWeekMs(now: now)
        let weekKey = HarnessTokenTimeWindow.dayKey(
            for: Date(timeIntervalSince1970: Double(weekStartMs) / 1000)
        )
        var allTime = HarnessTokenUsage.zero
        var today = HarnessTokenUsage.zero
        var thisWeek = HarnessTokenUsage.zero
        for entry in buckets {
            allTime = allTime.adding(entry.usage)
            if entry.day == todayKey { today = today.adding(entry.usage) }
            // day 是 yyyy-MM-dd，等长字符串的字典序即时间序
            if entry.day >= weekKey { thisWeek = thisWeek.adding(entry.usage) }
        }
        return (allTime, today, thisWeek)
    }

    // MARK: - 按天

    /// 每来源每天（口径与全量 harnessDaily 一致：上海自然日、无数据不出现）
    private func harnessSourceDaily(_ db: OpaquePointer) -> [TokenSourceID: [HarnessDailyUsage]] {
        let offset = HarnessTokenTimeWindow.utcOffsetSeconds
        let sql = """
        SELECT source, (ts_ms / 1000 + \(offset)) / 86400 AS day_index,
               COALESCE(SUM(uncached_in), 0), COALESCE(SUM(output), 0),
               COALESCE(SUM(cache_read), 0), COALESCE(SUM(cache_write), 0), COUNT(*)
        FROM harness_token_event
        GROUP BY source, day_index
        ORDER BY day_index ASC;
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            logger.warning("Harness 按来源按天聚合准备失败: " + String(cString: sqlite3_errmsg(db)))
            return [:]
        }
        var result: [TokenSourceID: [HarnessDailyUsage]] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let source = sourceID(stmt, 0) else { continue }
            let dayKey = HarnessTokenTimeWindow.dayKey(dayIndex: sqlite3_column_int64(stmt, 1))
            result[source, default: []].append(HarnessDailyUsage(
                day: dayKey,
                usage: HarnessTokenUsage(
                    uncachedInput: Int(sqlite3_column_int64(stmt, 2)),
                    output: Int(sqlite3_column_int64(stmt, 3)),
                    cacheRead: Int(sqlite3_column_int64(stmt, 4)),
                    cacheWrite: Int(sqlite3_column_int64(stmt, 5)),
                    requestCount: Int(sqlite3_column_int64(stmt, 6))
                )
            ))
        }
        return result
    }

    // MARK: - 按小时（今日 + 昨日一条查询）

    /// 每来源今日 / 昨日 24 槽
    ///
    /// 两个窗口在**同一条查询**里用 CASE 分桶：今日与昨日的「小时」取值相同，
    /// 落在同一行 (source, hour_idx) 上也互不干扰（各自的 CASE 只吃自己时间段的行）。
    private func harnessSourceHourly(
        _ db: OpaquePointer,
        now: Date
    ) -> (today: [TokenSourceID: [HarnessHourlyUsage]], yesterday: [TokenSourceID: [HarnessHourlyUsage]]) {
        let todayStart = HarnessTokenTimeWindow.startOfDayMs(now: now)
        let dayMs = HarnessTokenTimeWindow.millisecondsPerDay
        let yesterdayStart = todayStart - dayMs
        let nowMs = Int64((now.timeIntervalSince1970 * 1000).rounded())
        let currentHour = HarnessTokenTimeWindow.hourIndex(forTsMs: nowMs)
        let offset = HarnessTokenTimeWindow.utcOffsetSeconds
        func window(_ from: Int64, _ to: Int64) -> String {
            let condition = "ts_ms >= \(from) AND ts_ms < \(to)"
            let parts = ["COUNT(*)", "uncached_in", "output", "cache_read", "cache_write"].map { field in
                field == "COUNT(*)" ? "COALESCE(SUM(CASE WHEN \(condition) THEN 1 ELSE 0 END), 0)"
                                    : "COALESCE(SUM(CASE WHEN \(condition) THEN \(field) ELSE 0 END), 0)"
            }
            return parts.joined(separator: ", ")
        }
        let todayColumns = window(todayStart, todayStart + dayMs)
        let yesterdayColumns = window(yesterdayStart, todayStart)
        let sql = """
        SELECT source, ((ts_ms / 1000 + \(offset)) / 3600) % 24 AS hour_idx,
               \(todayColumns), \(yesterdayColumns)
        FROM harness_token_event
        WHERE ts_ms >= \(yesterdayStart) AND ts_ms < \(todayStart + dayMs)
        GROUP BY source, hour_idx;
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            logger.warning("Harness 按来源按小时聚合准备失败: " + String(cString: sqlite3_errmsg(db)))
            return ([:], [:])
        }
        var today: [TokenSourceID: [HarnessHourlyUsage]] = [:]
        var yesterday: [TokenSourceID: [HarnessHourlyUsage]] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let source = sourceID(stmt, 0) else { continue }
            let hour = Int(sqlite3_column_int64(stmt, 1))
            guard (0..<24).contains(hour) else { continue }
            // 列序：source(0) / hour(1) + 今日 5 列 + 昨日 5 列
            if hour <= currentHour {
                var slots = today[source] ?? HarnessHourlyUsage.emptyDay()
                slots[hour] = HarnessHourlyUsage(hour: hour, usage: Self.hourlyUsage(stmt, base: 2))
                today[source] = slots
            }
            var yesterdaySlots = yesterday[source] ?? HarnessHourlyUsage.emptyDay()
            yesterdaySlots[hour] = HarnessHourlyUsage(hour: hour, usage: Self.hourlyUsage(stmt, base: 7))
            yesterday[source] = yesterdaySlots
        }
        return (today, yesterday)
    }

    /// 从「请求数 + 4 桶」列位置读一个小时槽用量
    private static func hourlyUsage(_ stmt: OpaquePointer, base: Int32) -> HarnessTokenUsage {
        HarnessTokenUsage(
            uncachedInput: Int(sqlite3_column_int64(stmt, base + 1)),
            output: Int(sqlite3_column_int64(stmt, base + 2)),
            cacheRead: Int(sqlite3_column_int64(stmt, base + 3)),
            cacheWrite: Int(sqlite3_column_int64(stmt, base + 4)),
            requestCount: Int(sqlite3_column_int64(stmt, base))
        )
    }

    // MARK: - 会话数

    /// 每来源已建立扫描记录的会话数
    private func harnessSourceSessionCounts(_ db: OpaquePointer) -> [TokenSourceID: Int] {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = "SELECT source, COUNT(*) FROM harness_session_scan GROUP BY source;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            logger.warning("Harness 按来源会话数准备失败: " + String(cString: sqlite3_errmsg(db)))
            return [:]
        }
        var result: [TokenSourceID: Int] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let source = sourceID(stmt, 0) else { continue }
            result[source] = Int(sqlite3_column_int64(stmt, 1))
        }
        return result
    }
}
