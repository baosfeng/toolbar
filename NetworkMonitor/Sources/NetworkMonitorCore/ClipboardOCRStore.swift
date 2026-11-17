import Foundation
import SQLite3

// MARK: - 剪贴板 OCR 结果回写实现

/// DatabaseManager 的 OCR 回写实现（接口隔离：见 ClipboardOCRRepository）
///
/// 只写一列、只走写连接串行队列：识别在后台完成，写库仍与采集写共用同一条串行队列，
/// 不存在第二条写路径，也不需要额外事务（单条 UPDATE 本身原子）。
extension DatabaseManager: ClipboardOCRRepository {

    public func updateClipboardItemOCRText(id: UUID, text: String) -> Bool {
        let key = id.uuidString.uppercased()
        return serialQueue.sync { () -> Bool in
            guard let db else {
                logger.debug("数据库未就绪，剪贴板 OCR 结果未回写")
                return false
            }
            let sql = "UPDATE clipboard_items SET ocr_text = ? WHERE id = ?;"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                logger.warning("剪贴板 OCR 回写准备失败: \(String(cString: sqlite3_errmsg(db)))")
                return false
            }
            // 空串是「确认无文字」的终态标记，必须落库为 '' 而不是 NULL
            sqlite3_bind_text_copy(stmt, 1, text)
            sqlite3_bind_text_copy(stmt, 2, key)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                logger.warning("剪贴板 OCR 回写失败: \(String(cString: sqlite3_errmsg(db)))")
                return false
            }
            return sqlite3_changes(db) > 0
        }
    }
}