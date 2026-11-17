import Foundation
import SQLite3

// MARK: - 剪贴板批量删除（多选删除）

/// 批量删除的实现 —— 独立成文件：同族门禁按类名前缀聚合行数，多选删除是新领域，
/// 塞进 `DatabaseManager+ClipboardRepository.swift` 只会撑大既有族。
///
/// 与单条删除共用 `clipDeleteBatch`（先取被删行、再删行、单事务），因此上层拿到的
/// 条目列表口径与 `deleteClipboardItem(id:)` 完全一致，图片回收不需要另写一套。
extension DatabaseManager: ClipboardBatchDeleteRepository {

    public func deleteClipboardItems(ids: Set<UUID>) -> [ClipboardItem] {
        guard !ids.isEmpty else { return [] }
        let keys = ids.map { $0.uuidString.uppercased() }.sorted()
        let placeholders = Array(repeating: "?", count: keys.count).joined(separator: ", ")
        let whereClause = " WHERE id IN (\(placeholders))"
        return serialQueue.sync { () -> [ClipboardItem] in
            guard let db else { return [] }
            let bind: (OpaquePointer?) -> Void = { [keys] stmt in
                for (offset, key) in keys.enumerated() {
                    // 占位符从 1 起编号，与 keys 的排序一致（删除条件与查询条件必须同序）
                    self.sqlite3_bind_text_copy(stmt, Int32(offset + 1), key)
                }
            }
            return clipDeleteBatch(db,
                                   selectSQL: "SELECT \(ClipboardSchema.columns) FROM clipboard_items\(whereClause);",
                                   deleteSQL: "DELETE FROM clipboard_items\(whereClause);",
                                   failureLabel: "剪贴板批量删除",
                                   bind: bind) ?? []
        }
    }
}
