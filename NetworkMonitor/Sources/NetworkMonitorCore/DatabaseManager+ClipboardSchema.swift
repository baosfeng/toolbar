import Foundation
import SQLite3

// MARK: - 建表与迁移（user_version 1 → 2）

extension DatabaseManager {

    /// 剪贴板表与索引的幂等创建，并把 PRAGMA user_version 由 1 迁到 2
    ///
    /// - Important: 直接操作 db 指针、不调度队列，只能在串行队列上下文（migrateIfNeeded()）
    ///   或单线程测试上下文调用；重复执行无副作用。
    func migrateClipboardSchema() {
        guard let db else {
            logger.debug("数据库未就绪，跳过剪贴板表迁移")
            return
        }
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

        guard clipUserVersion(db) < 2 else { return }
        if clipExec(db, "PRAGMA user_version = 2") {
            logger.info("数据迁移 v2 完成：剪贴板历史表已就绪")
        } else {
            logger.warning("数据迁移 v2 失败: \(String(cString: sqlite3_errmsg(db)))")
        }
    }
}

// MARK: - 剪贴板仓储共用辅助

/// 查询列顺序（与 clipItem(from:) 的下标一一对应）
///
/// 放宽为 internal：同模块的 DatabaseManager+ClipboardRepository.swift 需要复用
enum ClipboardSchema {
    static let columns = """
    id, kind, text, preview, image_path, image_width, image_height, content_hash, \
    source_bundle_id, source_app_name, copy_count, is_pinned, created_at, pinned_at, stack_position
    """
}

/// 以下方法放宽为 internal 的原因：SQLite 行映射与绑定辅助被同模块的
/// DatabaseManager+ClipboardRepository.swift 复用，private 会限制在单个文件内。
/// 均须在串行队列上下文内调用，命名以 clip 前缀避免与既有辅助冲突。
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

    /// 绑定可空整数：nil 绑定 NULL
    func clipBindIntOrNull(_ stmt: OpaquePointer?, _ index: Int32, _ value: Int?) {
        if let value {
            sqlite3_bind_int(stmt, index, Int32(value))
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    /// 读取可空整数列
    func clipIntOrNil(_ stmt: OpaquePointer?, _ index: Int32) -> Int? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        return Int(sqlite3_column_int(stmt, index))
    }

    /// 读取可空文本列
    func clipText(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL,
              let pointer = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: pointer)
    }

    /// 读取可空时间列（SQLite REAL 秒）
    func clipDateOrNil(_ stmt: OpaquePointer?, _ index: Int32) -> Date? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        return Date(timeIntervalSince1970: sqlite3_column_double(stmt, index))
    }

    /// 行映射：关键列（id / kind / content_hash）非法时返回 nil，调用方跳过该行
    func clipItem(from stmt: OpaquePointer?) -> ClipboardItem? {
        guard let stmt,
              let idText = clipText(stmt, 0), let id = UUID(uuidString: idText),
              let kindText = clipText(stmt, 1), let kind = ClipboardItemKind(rawValue: kindText),
              let hash = clipText(stmt, 7) else { return nil }
        return ClipboardItem(
            id: id,
            kind: kind,
            text: clipText(stmt, 2),
            preview: clipText(stmt, 3) ?? "",
            imagePath: clipText(stmt, 4),
            imageWidth: clipIntOrNil(stmt, 5),
            imageHeight: clipIntOrNil(stmt, 6),
            contentHash: hash,
            sourceBundleID: clipText(stmt, 8),
            sourceAppName: clipText(stmt, 9),
            copyCount: Int(sqlite3_column_int(stmt, 10)),
            isPinned: sqlite3_column_int(stmt, 11) != 0,
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 12)),
            pinnedAt: clipDateOrNil(stmt, 13),
            stackPosition: clipIntOrNil(stmt, 14)
        )
    }

    /// 遍历结果集并映射（须在语句 bind 完成后调用）
    func clipItems(from stmt: OpaquePointer?) -> [ClipboardItem] {
        var items: [ClipboardItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let item = clipItem(from: stmt) { items.append(item) }
        }
        return items
    }

    /// 按内容哈希回读单条（写入后取最新行）
    func clipItemByHash(_ db: OpaquePointer, _ contentHash: String) -> ClipboardItem? {
        let sql = "SELECT \(ClipboardSchema.columns) FROM clipboard_items WHERE content_hash = ?;"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.warning("剪贴板回读准备失败: \(String(cString: sqlite3_errmsg(db)))")
            return nil
        }
        sqlite3_bind_text(stmt, 1, (contentHash as NSString).utf8String, -1, nil)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return clipItem(from: stmt)
    }
}
