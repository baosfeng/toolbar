import Foundation
import SQLite3

// MARK: - 版本阶梯迁移（user_version 0 → 1 → 2 → 3…）

extension DatabaseManager {

    /// 按版本阶梯逐级迁移到 `ClipboardSchema.latestVersion`
    ///
    /// v1 / v2 段在本文件（建表与历史补版本），v3 起在 `ClipboardSchemaLadder.swift`。
    /// 每一级是一个独立段：`if clipUserVersion(db) < N` 里只做第 N 级自己的变更，
    /// 段尾把 `PRAGMA user_version` 写成 N。**不要在一段里改别的版本号**——
    /// 旧的一次性写法（先无条件建表、再 `guard version < 2`、最后无条件写 2）会让
    /// v3 段每次启动把版本写回 2，v3 永远重跑。
    ///
    /// - Important: 直接操作 db 指针、不调度队列，只能在串行队列上下文（migrateIfNeeded()）
    ///   或单线程测试上下文调用；重复执行无副作用。
    func migrateClipboardSchema() {
        guard let db else {
            logger.debug("数据库未就绪，跳过剪贴板表迁移")
            return
        }
        if clipUserVersion(db) < 1 {
            migrateClipboardToV1(db)
        }
        if clipUserVersion(db) < 2 {
            migrateClipboardToV2(db)
        }
        if clipUserVersion(db) < 3 {
            migrateClipboardToV3(db)
        }
        if clipUserVersion(db) < 4 {
            migrateClipboardToV4(db)
        }
    }

    // MARK: - v1：剪贴板历史表与索引

    private func migrateClipboardToV1(_ db: OpaquePointer) {
        let statements = [
            """
            CREATE TABLE IF NOT EXISTS clipboard_items (
              id               TEXT PRIMARY KEY,
              kind             TEXT NOT NULL,
              text             TEXT,
              preview          TEXT NOT NULL DEFAULT '',
              image_path       TEXT,
              image_width      INTEGER,
              image_height     INTEGER,
              content_hash     TEXT NOT NULL,
              source_bundle_id TEXT,
              source_app_name  TEXT,
              copy_count       INTEGER NOT NULL DEFAULT 1,
              is_pinned        INTEGER NOT NULL DEFAULT 0,
              created_at       REAL NOT NULL,
              pinned_at        REAL,
              stack_position   INTEGER
            );
            """,
            "CREATE UNIQUE INDEX IF NOT EXISTS idx_clipboard_content_hash ON clipboard_items(content_hash);",
            "CREATE INDEX IF NOT EXISTS idx_clipboard_order ON clipboard_items(is_pinned DESC, created_at DESC);",
        ]
        for sql in statements {
            guard clipExec(db, sql) else {
                logger.warning("剪贴板建表失败: \(String(cString: sqlite3_errmsg(db)))")
                return
            }
        }
        clipAdvanceVersion(db, to: 1, label: "剪贴板历史表已就绪")
    }

    // MARK: - v2：补齐列（结构与 v1 相同，无 ALTER）

    /// v2 段：v1 建表与索引即等同于 v2 的表结构，段内无 ALTER。
    ///
    /// 历史原因保留为独立段：老库（user_version = 0 但表已由旧的一次性逻辑建好）
    /// 走到这里只需补写版本号，不做任何结构变更。
    private func migrateClipboardToV2(_ db: OpaquePointer) {
        clipAdvanceVersion(db, to: 2, label: "剪贴板表结构 v2 就绪")
    }

    // MARK: - 版本阶梯共用

    /// 写完一级后把 user_version 推进到该级；失败只告警，不回写旧版本
    /// 放宽为 internal：v3 之后的迁移段在 `ClipboardSchemaLadder.swift`（同模块另一文件）
    func clipAdvanceVersion(_ db: OpaquePointer, to version: Int32, label: String) {
        if clipExec(db, "PRAGMA user_version = \(version)") {
            logger.info("数据迁移 v\(version) 完成：\(label)")
        } else {
            logger.warning("数据迁移 v\(version) 失败: \(String(cString: sqlite3_errmsg(db)))")
        }
    }
}

// MARK: - 共用辅助

/// 以下方法放宽为 internal 的原因：被同模块的 ClipboardSchemaMapping.swift /
/// DatabaseManager+ClipboardRepository.swift / Harness 建表复用，private 会限制在单个文件内。
extension DatabaseManager {

    /// 执行无返回值的 SQL，成功返回 true
    func clipExec(_ db: OpaquePointer, _ sql: String) -> Bool {
        sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    }

    /// 读取 PRAGMA user_version
    func clipUserVersion(_ db: OpaquePointer) -> Int32 {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &stmt, nil) == SQLITE_OK,
              sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return sqlite3_column_int(stmt, 0)
    }
}