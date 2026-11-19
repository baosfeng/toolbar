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

    /// 删板：**删条目 + 删板行在同一个事务里**（一个业务动作 = 一个事务）
    ///
    /// 原子性是硬要求：过去两步各开一个事务，条目删掉后若进程崩溃 / 板行删除失败，
    /// 留下来的就是「板在、条目全没」的半截态（T1）。现在任何一步失败都整体回滚，
    /// 用户看到的仍是完整的一块板。
    ///
    /// 不变量保留：返回值是被删条目（含 imagePath），供上层 `ClipboardImageGC` 回收图片；
    /// 失败返回空数组（板与条目都原样不动，没有图片需要回收）。
    public func deleteBoard(id: UUID) -> [ClipboardItem] {
        let key = id.uuidString.uppercased()
        return serialQueue.sync { () -> [ClipboardItem] in
            guard let db else { return [] }
            do {
                return try NetworkMonitorCore.withTransaction(db) { conn in
                    let doomed = try clipDeleteRows(conn,
                                                    selectSQL: "SELECT \(ClipboardSchema.columns) FROM clipboard_items WHERE board_id = ?;",
                                                    deleteSQL: "DELETE FROM clipboard_items WHERE board_id = ?;",
                                                    bind: { sqlite3_bind_text_copy($0, 1, key) })
                    // 故障注入：条目已经删掉了，此时抛错必须把条目一起回滚（T1 的复发点）
                    if deleteBoardFaultProbe?() == true {
                        throw DatabaseOperationError("删板故障注入：板行删除失败")
                    }
                    var stmt: OpaquePointer?
                    defer { sqlite3_finalize(stmt) }
                    guard sqlite3_prepare_v2(conn, "DELETE FROM clipboard_boards WHERE id = ?;", -1, &stmt, nil) == SQLITE_OK else {
                        throw DatabaseOperationError("删板准备失败: \(String(cString: sqlite3_errmsg(conn)))")
                    }
                    sqlite3_bind_text_copy(stmt, 1, key)
                    guard sqlite3_step(stmt) == SQLITE_DONE else {
                        throw DatabaseOperationError("删板失败: \(String(cString: sqlite3_errmsg(conn)))")
                    }
                    return doomed
                }
            } catch {
                logger.warning("剪贴板删板失败，已整体回滚（板与条目均未改动）: \(error)")
                return []
            }
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
