import Foundation
import SQLite3

// MARK: - 按范围清理索引

// 设计约束（改动前必读）：
// - 事件与扫描记录**同一事务、同一范围**删除。只删事件会让 harness_session_scan 残留
//   (size, mtime)，下一轮增量把这些会话判成「未变更」直接跳过 —— 用户看到「清了却永远不回来」；
// - 删除语句与 harnessClearAll 同源，避免两处判据漂移；
// - 范围查询（harnessPurgePreview）与删除必须共用 purgeSinceMs，否则会出现
//   「确认框说删 1200 条、实际删 3000 条」的错账。

/// Harness token 索引的清理实现（从 HarnessUsageIndexAggregation.swift 拆出）
///
/// 职责单一：按 `HarnessRebuildScope` 删事件与扫描记录，并保证两者**同事务、同范围**。
/// 「清空后重建」与「只清理不重建」都走这里，增量判定因此不会残留旧记录。
///
/// - Warning: 不得在 query(sql:handler:) 的回调内调用本扩展方法，否则死锁。
extension DatabaseManager {

    /// 按范围清理索引，返回删除的事件行数（-1 = 失败）
    ///
    /// 范围口径：
    /// - `.full`：两张表都清空
    /// - `.sinceDays(n)`：只清「最近 n 天内出现过事件」的会话 —— 事件按 ts_ms 判定，
    ///   扫描记录按 session_id 反查（扫描记录本身没有时间维度，只能跟着会话走）
    ///
    /// **两张表必须在同一事务里删**：只删事件的实现会让 `harness_session_scan`
    /// 残留 (size, mtime) 记录，下一轮增量扫描把这些会话判成「未变更」直接跳过，
    /// 用户看到的是「清了却永远不回来」。这里的 DELETE 语句与 harnessClearAll 同源。
    public func harnessPurge(scope: HarnessRebuildScope, now: Date) -> Int {
        // 来源维度在这里落地：清理只动该来源的事件与扫描记录，别的来源原样保留
        let (source, base) = scope.decomposed()
        return serialQueue.sync { () -> Int in
            guard let db, harnessMigrateSchema(db) else { return -1 }
            do {
                return try NetworkMonitorCore.withTransaction(db, mode: .immediate) { conn in
                    // 会话集合必须在删事件之前取：删完就再也查不到「最近 n 天有过事件」的会话了
                    let sessionIDs: [String]?
                    switch base {
                    case .full:
                        sessionIDs = []
                    case .sinceDays(let days):
                        sessionIDs = harnessRecentSessionIDs(conn,
                                                             sinceMs: Self.purgeSinceMs(now: now, days: days),
                                                             source: source)
                    case .source:
                        sessionIDs = []
                    }
                    guard let sessionIDs else { throw DatabaseOperationError("会话集合查询失败") }
                    let deleted = harnessPurgeEvents(conn, scope: base, now: now, source: source)
                    guard deleted >= 0,
                          harnessPurgeScanRecords(conn, scope: base, sessionIDs: sessionIDs,
                                                  source: source) else {
                        throw DatabaseOperationError("Harness 索引清理失败")
                    }
                    return deleted
                }
            } catch {
                logger.warning("Harness 索引清理失败，已回滚: \(error)")
                return -1
            }
        }
    }

    /// 来源过滤子句（source 来自闭枚举，取值只有固定几个 rawValue，无注入面）
    private static func sourceClause(_ source: TokenSourceID?) -> String {
        guard let source else { return "" }
        return " AND source = '" + source.rawValue + "'"
    }

    /// 删事件，返回删除行数（-1 = 失败）
    private func harnessPurgeEvents(_ db: OpaquePointer, scope: HarnessRebuildScope, now: Date,
                                    source: TokenSourceID?) -> Int {
        let filter = Self.sourceClause(source)
        let sql: String
        switch scope {
        case .full:
            // 全量 + 来源：只清该来源（不能退化成整表 DELETE）
            sql = filter.isEmpty ? "DELETE FROM harness_token_event;"
                                 : "DELETE FROM harness_token_event WHERE 1 = 1" + filter + ";"
        case .sinceDays(let days):
            let sinceMs = Self.purgeSinceMs(now: now, days: days)
            sql = "DELETE FROM harness_token_event WHERE ts_ms >= \(sinceMs)" + filter + ";"
        case .source(let id, let inner):
            // 理论上已被 decomposed() 剥掉；真走到这里按内层 + 该来源处理
            return harnessPurgeEvents(db, scope: inner, now: now, source: id)
        }
        guard clipExec(db, sql) else {
            logger.warning("Harness 事件清理失败: " + String(cString: sqlite3_errmsg(db)))
            return -1
        }
        return Int(sqlite3_changes(db))
    }

    /// 删扫描记录（与事件同一范围；只删事件不删记录 = 假清空）
    ///
    /// 扫描记录本身没有时间维度，只能按「哪些会话最近 n 天有过事件」跟着删。
    /// 因此会话集合必须在**删事件之前**取好，删完再删记录。
    private func harnessPurgeScanRecords(_ db: OpaquePointer,
                                        scope: HarnessRebuildScope,
                                        sessionIDs: [String],
                                        source: TokenSourceID?) -> Bool {
        let filter = Self.sourceClause(source)
        // 全量清理必须无条件清空扫描记录：这里如果沿用「按会话 id 列表删」，
        // .full 传进来的是空列表就会一条都不删，下一轮把全部会话判成「未变更」跳过，
        // 结果是「清了却永远不回来」的假清空（实测踩到过）。
        if case .full = scope {
            return clipExec(db, filter.isEmpty ? "DELETE FROM harness_session_scan;"
                                               : "DELETE FROM harness_session_scan WHERE 1 = 1" + filter + ";")
        }
        if sessionIDs.isEmpty { return true }
        let placeholders = Array(repeating: "?", count: sessionIDs.count).joined(separator: ", ")
        let sql = "DELETE FROM harness_session_scan WHERE session_id IN (\(placeholders))" + filter + ";"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.warning("Harness 扫描记录清理准备失败: " + String(cString: sqlite3_errmsg(db)))
            return false
        }
        for (offset, sessionID) in sessionIDs.enumerated() {
            sqlite3_bind_text_copy(stmt, Int32(offset + 1), sessionID)
        }
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            logger.warning("Harness 扫描记录清理失败: " + String(cString: sqlite3_errmsg(db)))
            return false
        }
        return true
    }

    /// 最近 n 天内出现过事件的会话 id（去重，升序稳定）
    private func harnessRecentSessionIDs(_ db: OpaquePointer, sinceMs: Int64,
                                        source: TokenSourceID?) -> [String]? {
        let sql = "SELECT DISTINCT session_id FROM harness_token_event WHERE ts_ms >= ?"
            + Self.sourceClause(source) + " ORDER BY session_id;"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.warning("Harness 会话集合查询准备失败: " + String(cString: sqlite3_errmsg(db)))
            return nil
        }
        sqlite3_bind_int64(stmt, 1, sinceMs)
        var ids: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let id = clipText(stmt, 0) { ids.append(id) }
        }
        return ids
    }

    /// 清理起点（毫秒）：今天 0 点往前推 (days - 1) 天（n = 1 即「今天」）
    static func purgeSinceMs(now: Date, days: Int) -> Int64 {
        let span = Int64(max(1, days) - 1)
        let startOfTodayMs = HarnessTokenTimeWindow.startOfDayMs(now: now)
        return startOfTodayMs - span * HarnessTokenTimeWindow.millisecondsPerDay
    }

    // MARK: - 预览计数（二次确认里写清「将删除多少条」）

    /// 按范围统计将会删除的事件行数（-1 = 失败），与 harnessPurge 用同一套判据
    ///
    /// 为什么单独有一条预览查询：确认弹窗要在**删除之前**告诉用户规模，
    /// 让「近 30 天」这类看似温和的选项也能被看清代价。判据必须与清理完全同源，
    /// 否则会出现「说删 1200 条、实际删 3000 条」的错账。
    public func harnessPurgePreview(scope: HarnessRebuildScope, now: Date) -> Int {
        withReadDB(0) { db -> Int in
            guard harnessMigrateSchema(db) else { return -1 }
            // 预览与清理必须同源：来源维度也一起算进来，否则「说删 1200 条」实际只删本源的
            let (source, base) = scope.decomposed()
            let filter = Self.sourceClause(source)
            let sql: String
            switch base {
            case .full:
                sql = filter.isEmpty ? "SELECT COUNT(*) FROM harness_token_event;"
                                     : "SELECT COUNT(*) FROM harness_token_event WHERE 1 = 1" + filter + ";"
            case .sinceDays(let days):
                sql = "SELECT COUNT(*) FROM harness_token_event WHERE ts_ms >= "
                    + String(Self.purgeSinceMs(now: now, days: days)) + filter + ";"
            case .source:
                sql = "SELECT COUNT(*) FROM harness_token_event WHERE 0;"
            }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
                  sqlite3_step(stmt) == SQLITE_ROW else {
                logger.warning("Harness 清理预览查询失败: " + String(cString: sqlite3_errmsg(db)))
                return -1
            }
            return Int(sqlite3_column_int64(stmt, 0))
        }
    }
}