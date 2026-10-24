import Foundation
import SQLite3

// MARK: - 聚合查询（按天 / 项目 / 模型）

/// Harness token 索引的聚合查询实现（写入与建表见 HarnessUsageIndexStore.swift）
///
/// - Warning: 不得在 query(sql:handler:) 的回调内调用本扩展方法，否则死锁。
extension DatabaseManager {

    // MARK: - 聚合查询

    public func harnessAggregate(now: Date) -> HarnessAggregate {
        serialQueue.sync { () -> HarnessAggregate in
            guard let db, harnessMigrateSchema(db) else { return .empty }
            let todayStart = HarnessTokenTimeWindow.startOfDayMs(now: now)
            let weekStart = HarnessTokenTimeWindow.startOfWeekMs(now: now)
            let dayMs = HarnessTokenTimeWindow.millisecondsPerDay
            let nowMs = Int64((now.timeIntervalSince1970 * 1000).rounded())
            let currentHour = HarnessTokenTimeWindow.hourIndex(forTsMs: nowMs)
            return HarnessAggregate(
                allTime: harnessSum(db, fromMs: nil, toMs: nil),
                today: harnessSum(db, fromMs: todayStart, toMs: todayStart + dayMs),
                thisWeek: harnessSum(db, fromMs: weekStart, toMs: nil),
                daily: harnessDaily(db),
                projects: harnessProjects(db),
                models: harnessModels(db),
                indexedSessions: harnessScanCount(db),
                todayHourly: harnessHourly(
                    db, fromMs: todayStart, toMs: todayStart + dayMs, maskAfterHour: currentHour
                ),
                yesterdayHourly: harnessHourly(
                    db, fromMs: todayStart - dayMs, toMs: todayStart, maskAfterHour: nil
                )
            )
        }
    }

    /// 区间求和（fromMs 含、toMs 不含；nil 表示不限）
    private func harnessSum(_ db: OpaquePointer, fromMs: Int64?, toMs: Int64?) -> HarnessTokenUsage {
        var sql = """
        SELECT COUNT(*), COALESCE(SUM(uncached_in), 0), COALESCE(SUM(output), 0),
               COALESCE(SUM(cache_read), 0), COALESCE(SUM(cache_write), 0)
        FROM harness_token_event
        """
        switch (fromMs, toMs) {
        case (.some, .some): sql += " WHERE ts_ms >= ? AND ts_ms < ?"
        case (.some, .none): sql += " WHERE ts_ms >= ?"
        case (.none, .some): sql += " WHERE ts_ms < ?"
        case (.none, .none): break
        }
        sql += ";"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.warning("Harness 求和查询准备失败: " + String(cString: sqlite3_errmsg(db)))
            return .zero
        }
        var index: Int32 = 1
        if let fromMs {
            sqlite3_bind_int64(stmt, index, fromMs)
            index += 1
        }
        if let toMs { sqlite3_bind_int64(stmt, index, toMs) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return .zero }
        return HarnessTokenUsage(
            uncachedInput: Int(sqlite3_column_int64(stmt, 1)),
            output: Int(sqlite3_column_int64(stmt, 2)),
            cacheRead: Int(sqlite3_column_int64(stmt, 3)),
            cacheWrite: Int(sqlite3_column_int64(stmt, 4)),
            requestCount: Int(sqlite3_column_int64(stmt, 0))
        )
    }

    /// 按上海时区自然小时聚合，返回固定 24 槽；无数据小时与晚于 maskAfterHour 的小时为 nil（缺省不补 0）
    private func harnessHourly(
        _ db: OpaquePointer,
        fromMs: Int64,
        toMs: Int64,
        maskAfterHour: Int?
    ) -> [HarnessHourlyUsage] {
        var slots = HarnessHourlyUsage.emptyDay()
        let offset = HarnessTokenTimeWindow.utcOffsetSeconds
        let sql = """
        SELECT ((ts_ms / 1000 + \(offset)) / 3600) % 24 AS hour_idx,
               COALESCE(SUM(uncached_in), 0), COALESCE(SUM(output), 0),
               COALESCE(SUM(cache_read), 0), COALESCE(SUM(cache_write), 0), COUNT(*)
        FROM harness_token_event
        WHERE ts_ms >= ? AND ts_ms < ?
        GROUP BY hour_idx
        ORDER BY hour_idx ASC;
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.warning("Harness 按小时聚合准备失败: " + String(cString: sqlite3_errmsg(db)))
            return slots
        }
        sqlite3_bind_int64(stmt, 1, fromMs)
        sqlite3_bind_int64(stmt, 2, toMs)
        while sqlite3_step(stmt) == SQLITE_ROW {
            let hour = Int(sqlite3_column_int64(stmt, 0))
            guard (0..<24).contains(hour) else { continue }
            if let maskAfterHour, hour > maskAfterHour { continue }
            slots[hour] = HarnessHourlyUsage(
                hour: hour,
                usage: HarnessTokenUsage(
                    uncachedInput: Int(sqlite3_column_int64(stmt, 1)),
                    output: Int(sqlite3_column_int64(stmt, 2)),
                    cacheRead: Int(sqlite3_column_int64(stmt, 3)),
                    cacheWrite: Int(sqlite3_column_int64(stmt, 4)),
                    requestCount: Int(sqlite3_column_int64(stmt, 5))
                )
            )
        }
        return slots
    }

    /// 按上海时区自然日聚合（无数据的日子不出现，UI 侧保留空缺）
    private func harnessDaily(_ db: OpaquePointer) -> [HarnessDailyUsage] {
        let offset = HarnessTokenTimeWindow.utcOffsetSeconds
        let sql = """
        SELECT (ts_ms / 1000 + \(offset)) / 86400 AS day_index,
               COALESCE(SUM(uncached_in), 0), COALESCE(SUM(output), 0),
               COALESCE(SUM(cache_read), 0), COALESCE(SUM(cache_write), 0), COUNT(*)
        FROM harness_token_event
        GROUP BY day_index
        ORDER BY day_index ASC;
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.warning("Harness 按天聚合准备失败: " + String(cString: sqlite3_errmsg(db)))
            return []
        }
        var result: [HarnessDailyUsage] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let dayKey = HarnessTokenTimeWindow.dayKey(dayIndex: sqlite3_column_int64(stmt, 0))
            let usage = HarnessTokenUsage(
                uncachedInput: Int(sqlite3_column_int64(stmt, 1)),
                output: Int(sqlite3_column_int64(stmt, 2)),
                cacheRead: Int(sqlite3_column_int64(stmt, 3)),
                cacheWrite: Int(sqlite3_column_int64(stmt, 4)),
                requestCount: Int(sqlite3_column_int64(stmt, 5))
            )
            result.append(HarnessDailyUsage(day: dayKey, usage: usage))
        }
        return result
    }

    /// 按项目聚合（cwd 为空的事件不归属任何项目）
    private func harnessProjects(_ db: OpaquePointer) -> [HarnessProjectUsage] {
        let sql = """
        SELECT cwd, COUNT(DISTINCT session_id), COALESCE(SUM(uncached_in), 0), COALESCE(SUM(output), 0),
               COALESCE(SUM(cache_read), 0), COALESCE(SUM(cache_write), 0), COUNT(*)
        FROM harness_token_event
        WHERE cwd <> ''
        GROUP BY cwd
        ORDER BY (SUM(uncached_in) + SUM(output) + SUM(cache_read) + SUM(cache_write)) DESC, cwd ASC;
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.warning("Harness 按项目聚合准备失败: " + String(cString: sqlite3_errmsg(db)))
            return []
        }
        var result: [HarnessProjectUsage] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let cwd = clipText(stmt, 0) else { continue }
            let usage = HarnessTokenUsage(
                uncachedInput: Int(sqlite3_column_int64(stmt, 2)),
                output: Int(sqlite3_column_int64(stmt, 3)),
                cacheRead: Int(sqlite3_column_int64(stmt, 4)),
                cacheWrite: Int(sqlite3_column_int64(stmt, 5)),
                requestCount: Int(sqlite3_column_int64(stmt, 6))
            )
            result.append(HarnessProjectUsage(
                path: cwd,
                displayName: HarnessProjectNaming.displayName(forPath: cwd),
                sessionCount: Int(sqlite3_column_int64(stmt, 1)),
                usage: usage
            ))
        }
        return result
    }

    /// 按模型聚合
    private func harnessModels(_ db: OpaquePointer) -> [HarnessModelUsage] {
        let sql = """
        SELECT provider, model, COALESCE(SUM(uncached_in), 0), COALESCE(SUM(output), 0),
               COALESCE(SUM(cache_read), 0), COALESCE(SUM(cache_write), 0), COUNT(*)
        FROM harness_token_event
        GROUP BY provider, model
        ORDER BY (SUM(uncached_in) + SUM(output) + SUM(cache_read) + SUM(cache_write)) DESC, model ASC;
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.warning("Harness 按模型聚合准备失败: " + String(cString: sqlite3_errmsg(db)))
            return []
        }
        var result: [HarnessModelUsage] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let usage = HarnessTokenUsage(
                uncachedInput: Int(sqlite3_column_int64(stmt, 2)),
                output: Int(sqlite3_column_int64(stmt, 3)),
                cacheRead: Int(sqlite3_column_int64(stmt, 4)),
                cacheWrite: Int(sqlite3_column_int64(stmt, 5)),
                requestCount: Int(sqlite3_column_int64(stmt, 6))
            )
            result.append(HarnessModelUsage(
                provider: clipText(stmt, 0) ?? "",
                model: clipText(stmt, 1) ?? "",
                usage: usage
            ))
        }
        return result
    }

    /// 已索引会话数
    private func harnessScanCount(_ db: OpaquePointer) -> Int {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM harness_session_scan;", -1, &stmt, nil) == SQLITE_OK,
              sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    // MARK: - 计数 / 清空

    public func harnessEventCount() -> Int {
        serialQueue.sync { () -> Int in
            guard let db, harnessMigrateSchema(db) else { return 0 }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM harness_token_event;", -1, &stmt, nil) == SQLITE_OK,
                  sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
            return Int(sqlite3_column_int64(stmt, 0))
        }
    }

    public func harnessClearAll() -> Bool {
        serialQueue.sync { () -> Bool in
            guard let db, harnessMigrateSchema(db) else { return false }
            guard clipExec(db, "BEGIN IMMEDIATE") else { return false }
            guard clipExec(db, "DELETE FROM harness_token_event;"),
                  clipExec(db, "DELETE FROM harness_session_scan;") else {
                _ = clipExec(db, "ROLLBACK")
                logger.warning("Harness 索引清空失败: " + String(cString: sqlite3_errmsg(db)))
                return false
            }
            guard clipExec(db, "COMMIT") else {
                _ = clipExec(db, "ROLLBACK")
                return false
            }
            return true
        }
    }
}
