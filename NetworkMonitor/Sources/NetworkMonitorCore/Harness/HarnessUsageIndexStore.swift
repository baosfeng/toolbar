import Foundation
import SQLite3

// MARK: - 建表（幂等）

/// Harness token 索引表
///
/// 说明：
/// - 复用 DatabaseManager 既有连接与串行队列，不新建第二套连接管理
/// - PRAGMA user_version 由 DatabaseManager 的迁移序列管理，这里只用 CREATE IF NOT EXISTS，
///   避免与剪贴板迁移的版本判断互相干扰
/// - 表结构：
///   harness_token_event(session_id, cwd, provider, model, ts_ms, uncached_in, output, cache_read, cache_write)
///   harness_session_scan(path, session_id, size, mtime_ms, scanned_at)
extension DatabaseManager {
    /// 幂等建表（须在串行队列上下文或单线程上下文调用）
    func harnessMigrateSchema(_ db: OpaquePointer) -> Bool {
        let statements = [
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
        for sql in statements {
            guard clipExec(db, sql) else {
                logger.warning("Harness 索引建表失败: " + String(cString: sqlite3_errmsg(db)))
                return false
            }
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
        serialQueue.sync { () -> [String: HarnessSessionScanRecord] in
            guard let db, harnessMigrateSchema(db) else { return [:] }
            var records: [String: HarnessSessionScanRecord] = [:]
            let sql = "SELECT path, session_id, size, mtime_ms, scanned_at FROM harness_session_scan;"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                logger.warning("Harness 扫描记录查询准备失败: " + String(cString: sqlite3_errmsg(db)))
                return [:]
            }
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let path = clipText(stmt, 0), let sessionID = clipText(stmt, 1) else { continue }
                records[path] = HarnessSessionScanRecord(
                    path: path,
                    sessionID: sessionID,
                    size: sqlite3_column_int64(stmt, 2),
                    mtimeMs: sqlite3_column_int64(stmt, 3),
                    scannedAt: sqlite3_column_double(stmt, 4)
                )
            }
            return records
        }
    }

    // MARK: - 写入

    public func harnessReplaceSession(
        record: HarnessSessionScanRecord,
        events: [HarnessTokenEvent],
        cwd: String
    ) -> Bool {
        serialQueue.sync { () -> Bool in
            guard let db, harnessMigrateSchema(db) else { return false }
            // 单会话整体在一个事务内完成：先删旧事件再插入，保证重复扫描幂等
            guard clipExec(db, "BEGIN IMMEDIATE") else {
                logger.warning("Harness 会话写入事务开启失败: " + String(cString: sqlite3_errmsg(db)))
                return false
            }
            guard harnessDeleteEvents(db, sessionID: record.sessionID) else {
                _ = clipExec(db, "ROLLBACK")
                return false
            }
            guard harnessInsertEvents(db, events: events, fallbackCwd: cwd) else {
                _ = clipExec(db, "ROLLBACK")
                return false
            }
            guard harnessUpsertScanRecord(db, record: record) else {
                _ = clipExec(db, "ROLLBACK")
                return false
            }
            guard clipExec(db, "COMMIT") else {
                _ = clipExec(db, "ROLLBACK")
                logger.warning("Harness 会话写入提交失败: " + String(cString: sqlite3_errmsg(db)))
                return false
            }
            return true
        }
    }

    /// 删除某会话的全部事件
    private func harnessDeleteEvents(_ db: OpaquePointer, sessionID: String) -> Bool {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "DELETE FROM harness_token_event WHERE session_id = ?;", -1, &stmt, nil) == SQLITE_OK else {
            logger.warning("Harness 事件删除准备失败: " + String(cString: sqlite3_errmsg(db)))
            return false
        }
        sqlite3_bind_text(stmt, 1, (sessionID as NSString).utf8String, -1, nil)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            logger.warning("Harness 事件删除失败: " + String(cString: sqlite3_errmsg(db)))
            return false
        }
        return true
    }

    /// 批量插入事件（复用预处理语句）
    private func harnessInsertEvents(_ db: OpaquePointer, events: [HarnessTokenEvent], fallbackCwd: String) -> Bool {
        guard !events.isEmpty else { return true }
        let sql = """
        INSERT INTO harness_token_event
            (session_id, cwd, provider, model, ts_ms, uncached_in, output, cache_read, cache_write)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
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
            sqlite3_bind_text(stmt, 1, (event.sessionID as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (cwd as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 3, (event.provider as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 4, (event.model as NSString).utf8String, -1, nil)
            sqlite3_bind_int64(stmt, 5, event.tsMs)
            sqlite3_bind_int64(stmt, 6, Int64(event.usage.uncachedInput))
            sqlite3_bind_int64(stmt, 7, Int64(event.usage.output))
            sqlite3_bind_int64(stmt, 8, Int64(event.usage.cacheRead))
            sqlite3_bind_int64(stmt, 9, Int64(event.usage.cacheWrite))
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                logger.warning("Harness 事件写入失败: " + String(cString: sqlite3_errmsg(db)))
                return false
            }
        }
        return true
    }

    /// 写入 / 更新扫描记录
    private func harnessUpsertScanRecord(_ db: OpaquePointer, record: HarnessSessionScanRecord) -> Bool {
        let sql = """
        INSERT INTO harness_session_scan (path, session_id, size, mtime_ms, scanned_at)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(path) DO UPDATE SET
            session_id = excluded.session_id, size = excluded.size,
            mtime_ms = excluded.mtime_ms, scanned_at = excluded.scanned_at;
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.warning("Harness 扫描记录写入准备失败: " + String(cString: sqlite3_errmsg(db)))
            return false
        }
        sqlite3_bind_text(stmt, 1, (record.path as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (record.sessionID as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(stmt, 3, record.size)
        sqlite3_bind_int64(stmt, 4, record.mtimeMs)
        sqlite3_bind_double(stmt, 5, record.scannedAt)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            logger.warning("Harness 扫描记录写入失败: " + String(cString: sqlite3_errmsg(db)))
            return false
        }
        return true
    }
}
