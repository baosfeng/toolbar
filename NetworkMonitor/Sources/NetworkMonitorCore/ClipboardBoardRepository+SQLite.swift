import Foundation
import SQLite3

// MARK: - 板归属对清理的豁免判据

extension DatabaseManager {
    /// 可被超限 / 过期清理的条目判据：星标（is_pinned）与板归属（board_id）各自豁免
    ///
    /// 放在板这一侧而不是清理那一侧：口径变更的最可能原因是板的语义变化。
    static let pruneEligible = "is_pinned = 0 AND board_id IS NULL"
}

// MARK: - 剪贴板板仓储实现

/// `DatabaseManager` 的板仓储实现（接口隔离：见 `ClipboardBoardRepository`）
///
/// 写入一律经 `serialQueue`（写连接），只读查询经 `withReadDB`；
/// 列定义与行映射见 `ClipboardSchemaMapping.swift`，v4 建表见 `ClipboardSchemaLadder.swift`。
/// - Warning: 不得在 `query(sql:handler:)` 回调内或串行队列上下文调用，否则死锁。
extension DatabaseManager: ClipboardBoardRepository {

    // MARK: - 查询

    public func fetchBoards() -> [ClipboardBoard] {
        withReadDB([]) { db -> [ClipboardBoard] in
            let sql = """
            SELECT id, name, color_index, sort_order, created_at FROM clipboard_boards
            ORDER BY sort_order ASC, created_at ASC;
            """
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                logger.warning("剪贴板板查询准备失败: \(String(cString: sqlite3_errmsg(db)))")
                return []
            }
            var boards: [ClipboardBoard] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let board = clipBoard(from: stmt) { boards.append(board) }
            }
            return boards
        }
    }

    public func fetchClipboardItems(boardID: UUID) -> [ClipboardItem] {
        let key = boardID.uuidString.uppercased()
        return withReadDB([]) { db -> [ClipboardItem] in
            let sql = """
            SELECT \(ClipboardSchema.columns) FROM clipboard_items
            WHERE board_id = ? ORDER BY is_pinned DESC, created_at DESC;
            """
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                logger.warning("剪贴板板内查询准备失败: \(String(cString: sqlite3_errmsg(db)))")
                return []
            }
            sqlite3_bind_text_copy(stmt, 1, key)
            return clipItems(from: stmt)
        }
    }

    // MARK: - 写入

    public func createBoard(name: String) -> ClipboardBoard? {
        let normalized = ClipboardBoard.normalizedName(name)
        let newID = UUID().uuidString
        return serialQueue.sync { () -> ClipboardBoard? in
            guard let db else {
                logger.debug("数据库未就绪，剪贴板板未创建")
                return nil
            }
            // 顺序排在末位、色板下标按现有板数轮转：两者都在同一事务里读，避免并发建板重号
            var sortOrder = 0
            var existing = 0
            var countStmt: OpaquePointer?
            defer { sqlite3_finalize(countStmt) }
            if sqlite3_prepare_v2(db, "SELECT COUNT(*), COALESCE(MAX(sort_order), 0) FROM clipboard_boards;",
                                  -1, &countStmt, nil) == SQLITE_OK,
               sqlite3_step(countStmt) == SQLITE_ROW {
                existing = Int(sqlite3_column_int(countStmt, 0))
                sortOrder = Int(sqlite3_column_int(countStmt, 1)) + 1
            }
            let colorIndex = existing % ClipboardBoard.colorCount
            // id 与仓储既有口径一致写大写：条目侧 board_id 也按大写比对
            let sql = """
            INSERT INTO clipboard_boards (id, name, color_index, sort_order, created_at)
            VALUES (?, ?, ?, ?, ?);
            """
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                logger.warning("剪贴板建板准备失败: \(String(cString: sqlite3_errmsg(db)))")
                return nil
            }
            sqlite3_bind_text_copy(stmt, 1, newID)
            sqlite3_bind_text_copy(stmt, 2, normalized)
            sqlite3_bind_int(stmt, 3, Int32(colorIndex))
            sqlite3_bind_int(stmt, 4, Int32(sortOrder))
            sqlite3_bind_double(stmt, 5, Date().timeIntervalSince1970)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                logger.warning("剪贴板建板失败: \(String(cString: sqlite3_errmsg(db)))")
                return nil
            }
            return clipBoardByID(db, newID)
        }
    }

    public func renameBoard(id: UUID, name: String) -> Bool {
        let key = id.uuidString.uppercased()
        let normalized = ClipboardBoard.normalizedName(name)
        return serialQueue.sync { () -> Bool in
            guard let db else { return false }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, "UPDATE clipboard_boards SET name = ? WHERE id = ?;",
                                     -1, &stmt, nil) == SQLITE_OK else {
                logger.warning("剪贴板改板名准备失败: \(String(cString: sqlite3_errmsg(db)))")
                return false
            }
            sqlite3_bind_text_copy(stmt, 1, normalized)
            sqlite3_bind_text_copy(stmt, 2, key)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                logger.warning("剪贴板改板名失败: \(String(cString: sqlite3_errmsg(db)))")
                return false
            }
            return sqlite3_changes(db) > 0
        }
    }

    public func deleteBoard(id: UUID) -> [ClipboardItem] {
        let key = id.uuidString.uppercased()
        return serialQueue.sync { () -> [ClipboardItem] in
            guard let db else { return [] }
            // 先删条目（走 clipDeleteBatch，自带事务并返回被删行供上层回收图片），再删板本身。
            // 两步不共享事务：条目删除失败时直接返回、板表原样不动，因此不会留下「板在、条目全没」的半截态。
            let doomed = clipDeleteBatch(db,
                                         selectSQL: "SELECT \(ClipboardSchema.columns) FROM clipboard_items WHERE board_id = ?;",
                                         deleteSQL: "DELETE FROM clipboard_items WHERE board_id = ?;",
                                         failureLabel: "剪贴板删板（条目）",
                                         bind: { sqlite3_bind_text_copy($0, 1, key) })
            guard let doomed else {
                // clipDeleteBatch 内部已回滚；板表未动，状态一致
                return []
            }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, "DELETE FROM clipboard_boards WHERE id = ?;", -1, &stmt, nil) == SQLITE_OK else {
                logger.warning("剪贴板删板准备失败: \(String(cString: sqlite3_errmsg(db)))")
                return doomed
            }
            sqlite3_bind_text_copy(stmt, 1, key)
            if sqlite3_step(stmt) != SQLITE_DONE {
                logger.warning("剪贴板删板失败: \(String(cString: sqlite3_errmsg(db)))")
            }
            return doomed
        }
    }

    public func moveItemToBoard(itemID: UUID, boardID: UUID?) -> Bool {
        let key = itemID.uuidString.uppercased()
        let boardKey = boardID?.uuidString.uppercased()
        return serialQueue.sync { () -> Bool in
            guard let db else { return false }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, "UPDATE clipboard_items SET board_id = ? WHERE id = ?;",
                                     -1, &stmt, nil) == SQLITE_OK else {
                logger.warning("剪贴板移板准备失败: \(String(cString: sqlite3_errmsg(db)))")
                return false
            }
            sqlite3_bind_text_or_null(stmt, 1, boardKey)
            sqlite3_bind_text_copy(stmt, 2, key)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                logger.warning("剪贴板移板失败: \(String(cString: sqlite3_errmsg(db)))")
                return false
            }
            return sqlite3_changes(db) > 0
        }
    }

    // MARK: - 行映射

    /// 单行 → 板；id 非法时返回 nil（调用方跳过该行）
    ///
    /// 放宽为 internal 的原因：与 `clipItem(from:)` 同族，日后板内其他查询复用同一映射。
    func clipBoard(from stmt: OpaquePointer?) -> ClipboardBoard? {
        guard let stmt,
              let idText = clipText(stmt, 0),
              let id = UUID(uuidString: idText),
              let name = clipText(stmt, 1) else { return nil }
        return ClipboardBoard(
            id: id,
            name: name,
            colorIndex: Int(sqlite3_column_int(stmt, 2)),
            sortOrder: Int(sqlite3_column_int(stmt, 3)),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4))
        )
    }

    /// 按 id 回读单块板（建板后取刚落库的行）
    private func clipBoardByID(_ db: OpaquePointer, _ idText: String) -> ClipboardBoard? {
        let sql = "SELECT id, name, color_index, sort_order, created_at FROM clipboard_boards WHERE id = ?;"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.warning("剪贴板板回读准备失败: \(String(cString: sqlite3_errmsg(db)))")
            return nil
        }
        sqlite3_bind_text_copy(stmt, 1, idText)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return clipBoard(from: stmt)
    }
}
