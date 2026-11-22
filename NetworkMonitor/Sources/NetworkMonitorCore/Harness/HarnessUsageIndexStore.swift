import Foundation
import SQLite3

// MARK: - 建表（幂等）

/// Harness token 索引表
///
/// 说明：
/// - 复用 DatabaseManager 既有连接与串行队列，不新建第二套连接管理
/// - PRAGMA user_version 由 DatabaseManager 的迁移序列管理，这里只用
///   CREATE IF NOT EXISTS 与 PRAGMA table_info + ALTER，避免与剪贴板迁移的版本判断互相干扰
/// - 表结构（`source` 由多来源接入引入；默认 'dsh' 让既有数据零迁移）：
///   harness_token_event(session_id, cwd, provider, model, ts_ms, uncached_in, output, cache_read, cache_write, source)
///   harness_session_scan(path, session_id, size, mtime_ms, scanned_at, source)
///
/// 主键是 path 而非 (path, source)：前提是各来源根目录互斥（dsh/Claude/Codex 默认路径
/// 互不相同），会话文件绝对路径天然唯一。前提被打破（两个来源 rootPath 指到同一目录）
/// 的现象：后写入方覆盖前者的扫描记录，某个来源的会话数忽多忽少、增量把别人的文件当成
/// 自己扫过。要支持重叠目录须把主键改为 (path, source) 并做表重建迁移。
extension DatabaseManager {
    /// 建表语句（可重复执行）
    private static let harnessCreateStatements = [
        """
        CREATE TABLE IF NOT EXISTS harness_token_event (
          session_id  TEXT NOT NULL,
          cwd         TEXT NOT NULL DEFAULT '',
          provider    TEXT NOT NULL DEFAULT '',
          model       TEXT NOT NULL DEFAULT '',
          ts_ms       INTEGER NOT NULL,
          uncached_in INTEGER NOT NULL DEFAULT 0,
          output      INTEGER NOT NULL DEFAULT 0,
          cache_read  INTEGER NOT NULL DEFAULT 0,
          cache_write INTEGER NOT NULL DEFAULT 0
        );
        """,
        "CREATE INDEX IF NOT EXISTS idx_harness_event_ts ON harness_token_event(ts_ms);",
        "CREATE INDEX IF NOT EXISTS idx_harness_event_session ON harness_token_event(session_id);",
        "CREATE INDEX IF NOT EXISTS idx_harness_event_cwd ON harness_token_event(cwd);",
        """
        CREATE TABLE IF NOT EXISTS harness_session_scan (
          path       TEXT PRIMARY KEY,
          session_id TEXT NOT NULL,
          size       INTEGER NOT NULL,
          mtime_ms   INTEGER NOT NULL,
          scanned_at REAL NOT NULL
        );
        """,
    ]

    /// `source` 列建好之后才能建的索引（老库升级时列还不存在，顺序不能提前）
    private static let harnessSourceIndexStatements = [
        "CREATE INDEX IF NOT EXISTS idx_harness_event_source ON harness_token_event(source);",
    ]

    /// 幂等建表 + 加列 + 建索引（须在串行队列上下文或单线程上下文调用）
    func harnessMigrateSchema(_ db: OpaquePointer) -> Bool {
        for sql in Self.harnessCreateStatements {
            guard clipExec(db, sql) else {
                logger.warning("Harness 索引建表失败: " + String(cString: sqlite3_errmsg(db)))
                return false
            }
        }
        // ALTER TABLE ... ADD COLUMN 重复执行会报错，故先查 PRAGMA table_info
        guard harnessEnsureColumn(db, table: "harness_token_event", column: "source",
                                  definition: "TEXT NOT NULL DEFAULT 'dsh'"),
              harnessEnsureColumn(db, table: "harness_session_scan", column: "source",
                                  definition: "TEXT NOT NULL DEFAULT 'dsh'") else {
            return false
        }
        for sql in Self.harnessSourceIndexStatements {
            guard clipExec(db, sql) else {
                logger.warning("Harness 来源索引创建失败: " + String(cString: sqlite3_errmsg(db)))
                return false
            }
        }
        return true
    }

    /// 表里是否已有该列（PRAGMA table_info 逐行比对列名）
    private func harnessHasColumn(_ db: OpaquePointer, table: String, column: String) -> Bool {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(table));", -1, &stmt, nil) == SQLITE_OK else {
            logger.warning("Harness 表结构检查失败（\(table)）: " + String(cString: sqlite3_errmsg(db)))
            return false
        }
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let name = clipText(stmt, 1), name == column { return true }
        }
        return false
    }

    /// 缺列才加（幂等）；已存在时直接返回 true
    private func harnessEnsureColumn(
        _ db: OpaquePointer,
        table: String,
        column: String,
        definition: String
    ) -> Bool {
        if harnessHasColumn(db, table: table, column: column) { return true }
        guard clipExec(db, "ALTER TABLE \(table) ADD COLUMN \(column) \(definition);") else {
            logger.warning("Harness 加列失败（\(table).\(column)）: " + String(cString: sqlite3_errmsg(db)))
            return false
        }
        return true
    }
}

// MARK: - 仓储实现

/// DatabaseManager 的 Token 索引仓储实现（见 HarnessTokenRepository）
///
/// - Warning: 不得在 query(sql:handler:) 的回调内调用本扩展方法，否则死锁。
extension DatabaseManager: HarnessTokenRepository {

    // MARK: - 建表

    public func migrateHarnessSchema() -> Bool {
        serialQueue.sync { () -> Bool in
            guard let db else { return false }
            return harnessMigrateSchema(db)
        }
    }

    // MARK: - 扫描记录

    public func harnessScanRecords() -> [String: HarnessSessionScanRecord] {
        harnessScanRecords(source: nil)
    }

    public func harnessScanRecords(source: TokenSourceID?) -> [String: HarnessSessionScanRecord] {
        withReadDB([:]) { db -> [String: HarnessSessionScanRecord] in
            guard harnessMigrateSchema(db) else { return [:] }
            var records: [String: HarnessSessionScanRecord] = [:]
            // source 为 nil 时条件是恒真式而不是拼两条 SQL：列序与读取路径只有一份
            let sql = """
            SELECT path, session_id, size, mtime_ms, scanned_at, source
            FROM harness_session_scan
            WHERE (? IS NULL OR source = ?);
            """
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                logger.warning("Harness 扫描记录查询准备失败: " + String(cString: sqlite3_errmsg(db)))
                return [:]
            }
            if let source {
                sqlite3_bind_text_copy(stmt, 1, source.rawValue)
                sqlite3_bind_text_copy(stmt, 2, source.rawValue)
            } else {
                sqlite3_bind_null(stmt, 1)
                sqlite3_bind_null(stmt, 2)
            }
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let path = clipText(stmt, 0), let sessionID = clipText(stmt, 1) else { continue }
                let rawSource = clipText(stmt, 5) ?? TokenSourceID.legacy.rawValue
                records[path] = HarnessSessionScanRecord(
                    path: path,
                    sessionID: sessionID,
                    size: sqlite3_column_int64(stmt, 2),
                    mtimeMs: sqlite3_column_int64(stmt, 3),
                    scannedAt: sqlite3_column_double(stmt, 4),
                    source: TokenSourceID(rawValue: rawSource) ?? .legacy
                )
            }
            return records
        }
    }

    // MARK: - 按来源统计

    public func harnessSourceCounts() -> [HarnessSourceIndexCount] {
        withReadDB([]) { db -> [HarnessSourceIndexCount] in
            guard harnessMigrateSchema(db) else { return [] }
            let events = harnessCountBySource(db, sql: "SELECT source, COUNT(*) FROM harness_token_event GROUP BY source;")
            let sessions = harnessCountBySource(db, sql: "SELECT source, COUNT(*) FROM harness_session_scan GROUP BY source;")
            // 按 allCases 顺序输出，保证设置页行序稳定；未知 rawValue 不展示（避免空行）
            return TokenSourceID.allCases.compactMap { source in
                let eventCount = events[source.rawValue] ?? 0
                let sessionCount = sessions[source.rawValue] ?? 0
                guard eventCount > 0 || sessionCount > 0 else { return nil }
                return HarnessSourceIndexCount(source: source, eventCount: eventCount, sessionCount: sessionCount)
            }
        }
    }

    /// `GROUP BY source` 的通用计数读取
    private func harnessCountBySource(_ db: OpaquePointer, sql: String) -> [String: Int] {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.warning("Harness 来源统计准备失败: " + String(cString: sqlite3_errmsg(db)))
            return [:]
        }
        var result: [String: Int] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let raw = clipText(stmt, 0) else { continue }
            result[raw] = Int(sqlite3_column_int64(stmt, 1))
        }
        return result
    }

    // MARK: - 写入

    /// 兼容入口：未指定来源的写入按 DSH 记账（既有扫描器走的正是这条）
    public func harnessReplaceSession(
        record: HarnessSessionScanRecord,
        events: [HarnessTokenEvent],
        cwd: String
    ) -> Bool {
        harnessReplaceSession(record: record, events: events, cwd: cwd, source: .dsh)
    }

    public func harnessReplaceSession(
        record: HarnessSessionScanRecord,
        events: [HarnessTokenEvent],
        cwd: String,
        source: TokenSourceID
    ) -> Bool {
        serialQueue.sync { () -> Bool in
            guard let db, harnessMigrateSchema(db) else { return false }
            // 单会话整体在一个事务内完成：先删旧事件再插入，保证重复扫描幂等
            do {
                try NetworkMonitorCore.withTransaction(db, mode: .immediate) { conn in
                    guard harnessDeleteEvents(conn, sessionID: record.sessionID, source: source) else {
                        throw DatabaseOperationError("Harness 事件删除失败")
                    }
                    guard harnessInsertEvents(conn, events: events, fallbackCwd: cwd, source: source) else {
                        throw DatabaseOperationError("Harness 事件写入失败")
                    }
                    guard harnessUpsertScanRecord(conn, record: record, source: source) else {
                        throw DatabaseOperationError("Harness 扫描记录写入失败")
                    }
                }
            } catch {
                logger.warning("Harness 会话写入失败，已回滚: \(error)")
                return false
            }
            return true
        }
    }

    /// 删除某会话在某来源下的全部事件
    ///
    /// 按 (session_id, source) 定位：多来源共用一张表，各家的会话 id 空间互不相干，
    /// 只按 session_id 删会误伤同名会话。
    private func harnessDeleteEvents(_ db: OpaquePointer, sessionID: String, source: TokenSourceID) -> Bool {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "DELETE FROM harness_token_event WHERE session_id = ? AND source = ?;", -1, &stmt, nil) == SQLITE_OK else {
            logger.warning("Harness 事件删除准备失败: " + String(cString: sqlite3_errmsg(db)))
            return false
        }
        sqlite3_bind_text_copy(stmt, 1, sessionID)
        sqlite3_bind_text_copy(stmt, 2, source.rawValue)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            logger.warning("Harness 事件删除失败: " + String(cString: sqlite3_errmsg(db)))
            return false
        }
        return true
    }

    /// 批量插入事件（复用预处理语句）
    private func harnessInsertEvents(
        _ db: OpaquePointer,
        events: [HarnessTokenEvent],
        fallbackCwd: String,
        source: TokenSourceID
    ) -> Bool {
        guard !events.isEmpty else { return true }
        let sql = """
        INSERT INTO harness_token_event
            (session_id, cwd, provider, model, ts_ms, uncached_in, output, cache_read, cache_write, source)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.warning("Harness 事件写入准备失败: " + String(cString: sqlite3_errmsg(db)))
            return false
        }
        for event in events {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
            let cwd = event.cwd.isEmpty ? fallbackCwd : event.cwd
            sqlite3_bind_text_copy(stmt, 1, event.sessionID)
            sqlite3_bind_text_copy(stmt, 2, cwd)
            sqlite3_bind_text_copy(stmt, 3, event.provider)
            sqlite3_bind_text_copy(stmt, 4, event.model)
            sqlite3_bind_int64(stmt, 5, event.tsMs)
            sqlite3_bind_int64(stmt, 6, Int64(event.usage.uncachedInput))
            sqlite3_bind_int64(stmt, 7, Int64(event.usage.output))
            sqlite3_bind_int64(stmt, 8, Int64(event.usage.cacheRead))
            sqlite3_bind_int64(stmt, 9, Int64(event.usage.cacheWrite))
            sqlite3_bind_text_copy(stmt, 10, source.rawValue)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                logger.warning("Harness 事件写入失败: " + String(cString: sqlite3_errmsg(db)))
                return false
            }
        }
        return true
    }

    /// 写入 / 更新扫描记录
    private func harnessUpsertScanRecord(
        _ db: OpaquePointer,
        record: HarnessSessionScanRecord,
        source: TokenSourceID
    ) -> Bool {
        let sql = """
        INSERT INTO harness_session_scan (path, session_id, size, mtime_ms, scanned_at, source)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(path) DO UPDATE SET
            session_id = excluded.session_id, size = excluded.size,
            mtime_ms = excluded.mtime_ms, scanned_at = excluded.scanned_at,
            source = excluded.source;
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.warning("Harness 扫描记录写入准备失败: " + String(cString: sqlite3_errmsg(db)))
            return false
        }
        sqlite3_bind_text_copy(stmt, 1, record.path)
        sqlite3_bind_text_copy(stmt, 2, record.sessionID)
        sqlite3_bind_int64(stmt, 3, record.size)
        sqlite3_bind_int64(stmt, 4, record.mtimeMs)
        sqlite3_bind_double(stmt, 5, record.scannedAt)
        sqlite3_bind_text_copy(stmt, 6, source.rawValue)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            logger.warning("Harness 扫描记录写入失败: " + String(cString: sqlite3_errmsg(db)))
            return false
        }
        return true
    }
}
