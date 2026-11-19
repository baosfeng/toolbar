import Foundation
import SQLite3

// MARK: - 剪贴板栈顺序（Paste Stack）

/// 栈顺序重排 —— 从 `DatabaseManager+ClipboardRepository.swift` 拆出：
/// 采集 / 查询 / 删除 / 清空都是条目生命周期，栈顺序是「用户手动的排列」这条独立职责。
extension DatabaseManager {

    public func updateClipboardStackPositions(_ orderedIDs: [UUID]) {
        serialQueue.sync { () -> Void in
            guard let db else { return }
            // 整体在单事务内完成：中途失败则回滚，避免留下半截编号
            do {
                try NetworkMonitorCore.withTransaction(db) { conn in
                    guard clipExec(conn, "UPDATE clipboard_items SET stack_position = NULL;") else {
                        throw DatabaseOperationError("剪贴板栈清空失败: \(String(cString: sqlite3_errmsg(conn)))")
                    }
                    let sql = "UPDATE clipboard_items SET stack_position = ? WHERE id = ?;"
                    var stmt: OpaquePointer?
                    defer { sqlite3_finalize(stmt) }
                    guard sqlite3_prepare_v2(conn, sql, -1, &stmt, nil) == SQLITE_OK else {
                        throw DatabaseOperationError("剪贴板栈重排准备失败: \(String(cString: sqlite3_errmsg(conn)))")
                    }
                    for (offset, id) in orderedIDs.enumerated() {
                        sqlite3_reset(stmt)
                        sqlite3_clear_bindings(stmt)
                        sqlite3_bind_int(stmt, 1, Int32(offset + 1))
                        sqlite3_bind_text_copy(stmt, 2, id.uuidString.uppercased())
                        guard sqlite3_step(stmt) == SQLITE_DONE else {
                            throw DatabaseOperationError("剪贴板栈重排失败: \(String(cString: sqlite3_errmsg(conn)))")
                        }
                    }
                }
            } catch {
                logger.warning("剪贴板栈重排失败，已回滚: \(error)")
            }
        }
    }
}
