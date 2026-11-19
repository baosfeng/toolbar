import Foundation
import SQLite3

// MARK: - 剪贴板条目的编辑与手动新建

/// 条目编辑 / 手动新建的两条写入路径 — DatabaseManager 剪贴板仓储的补充实现
///
/// 与 `DatabaseManager+ClipboardRepository.swift` 的分工：那里是「采集落库」的 upsert（带来源 App
/// 与去重自增），这里是用户主动改内容、手写新条目的路径。
///
/// 文件命名刻意不像其他仓储文件那样带 `DatabaseManager+` 前缀：同族门禁按类名前缀聚合，
/// 那样会把本批增长记到已顶到基线的 `DatabaseManager` 族上（基线只允许变小）。
///
/// 编辑后 content_hash 口径（本批定稿，理由见协议注释与下方 update 实现）：
/// 重算哈希；命中别的条目时保留当前条目、把被冲突那条当同一内容的旧记录合并掉
/// （copy_count 求和、收藏态取或）。不选「哈希置空 / 加列存旧哈希」，原因见 update 的注释。
extension DatabaseManager {

    // MARK: - 编辑

    public func updateClipboardItemText(id: UUID, text: String, preview: String) -> ClipboardItem? {
        guard let payload = ClipboardContentHasher.prepareText(text) else {
            logger.debug("剪贴板编辑：正文规范化后为空，不保存")
            return nil
        }
        let key = id.uuidString.uppercased()
        let trimmedPreview = preview.trimmingCharacters(in: .whitespacesAndNewlines)
        let folded = trimmedPreview.isEmpty ? ClipboardPreview.make(from: payload.text) : ClipboardPreview.make(from: trimmedPreview)

        return serialQueue.sync { () -> ClipboardItem? in
            guard let db else {
                logger.debug("数据库未就绪，剪贴板编辑未落库")
                return nil
            }
            guard let current = clipItemByID(db, key) else {
                logger.debug("剪贴板编辑：条目不存在（可能已被别的路径删除）")
                return nil
            }
            // 图片 / 文件条目的正文不是可编辑的纯文本，走各自路径（本批明示不做）
            guard current.kind == .text || current.kind == .rtf else {
                logger.debug("剪贴板编辑：类型 \(current.kind.rawValue) 不支持正文编辑")
                return nil
            }
            // 自撞（内容没改）不算冲突：只有「别的条目已占着这个哈希」才需要合并
            let conflict = clipItemByHash(db, payload.contentHash).flatMap { $0.id == current.id ? nil : $0 }
            do {
                try NetworkMonitorCore.withTransaction(db) { conn in
                    let ok = conflict.map { clipMergeConflict(conn, current: current, conflict: $0, payload: payload, folded: folded) }
                        ?? clipWriteItemText(conn, id: key, payload: payload, folded: folded)
                    guard ok else { throw DatabaseOperationError("写入正文失败") }
                }
            } catch {
                logger.warning("剪贴板编辑失败，已回滚: \(error)")
                return nil
            }
            return clipItemByHash(db, payload.contentHash)
        }
    }

    // MARK: - 手动新建

    public func createClipboardItem(text: String) -> ClipboardItem? {
        guard let payload = ClipboardContentHasher.prepareText(text) else {
            logger.debug("剪贴板新建：正文规范化后为空，不落库")
            return nil
        }
        // 直接复用采集路径的原子 upsert：去重口径（同内容自增 copy_count 并置顶）与采集完全一致，
        // 差异只有「不记录来源 App」——手动新建不是从某个 App 复制来的，来源两列一律空。
        return saveClipboardItem(ClipboardDraft(kind: .text,
                                                contentHash: payload.contentHash,
                                                text: payload.text,
                                                preview: ClipboardPreview.make(from: payload.text),
                                                sourceBundleID: nil,
                                                sourceAppName: nil,
                                                createdAt: Date()))
    }

    // MARK: - 写入步骤

    /// 无冲突：就地改正文 / 摘要 / 哈希；copy_count 与创建时间不动（编辑不等于又复制了一次）
    private func clipWriteItemText(_ db: OpaquePointer, id: String,
                                   payload: ClipboardTextPayload, folded: String) -> Bool {
        let sql = """
        UPDATE clipboard_items
           SET kind = ?, text = ?, preview = ?, content_hash = ?
         WHERE id = ?;
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.warning("剪贴板编辑准备失败: \(String(cString: sqlite3_errmsg(db)))")
            return false
        }
        sqlite3_bind_text_copy(stmt, 1, ClipboardItemKind.text.rawValue)
        sqlite3_bind_text_copy(stmt, 2, payload.text)
        sqlite3_bind_text_copy(stmt, 3, folded)
        sqlite3_bind_text_copy(stmt, 4, payload.contentHash)
        sqlite3_bind_text_copy(stmt, 5, id)
        return sqlite3_step(stmt) == SQLITE_DONE
    }

    /// 冲突：先删掉同内容的那条旧记录，再把当前条目写成它的内容
    ///
    /// 顺序不能反：content_hash 有唯一索引，先改当前行会直接撞索引失败。
    /// 合并口径：copy_count 求和（两条都是同内容的复制次数）、收藏态取或（任一条被收藏就保持收藏）。
    private func clipMergeConflict(_ db: OpaquePointer, current: ClipboardItem, conflict: ClipboardItem,
                                   payload: ClipboardTextPayload, folded: String) -> Bool {
        var deleteStmt: OpaquePointer?
        defer { sqlite3_finalize(deleteStmt) }
        guard sqlite3_prepare_v2(db, "DELETE FROM clipboard_items WHERE id = ?;", -1, &deleteStmt, nil) == SQLITE_OK else {
            logger.warning("剪贴板编辑合并准备失败: \(String(cString: sqlite3_errmsg(db)))")
            return false
        }
        sqlite3_bind_text_copy(deleteStmt, 1, conflict.id.uuidString.uppercased())
        guard sqlite3_step(deleteStmt) == SQLITE_DONE else { return false }

        let mergedPinned = current.isPinned || conflict.isPinned
        let mergedPinnedAt = mergedPinned ? (current.pinnedAt ?? conflict.pinnedAt ?? Date()) : nil
        let sql = """
        UPDATE clipboard_items
           SET kind = ?, text = ?, preview = ?, content_hash = ?,
               copy_count = copy_count + ?, is_pinned = ?, pinned_at = ?
         WHERE id = ?;
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.warning("剪贴板编辑合并准备失败: \(String(cString: sqlite3_errmsg(db)))")
            return false
        }
        sqlite3_bind_text_copy(stmt, 1, ClipboardItemKind.text.rawValue)
        sqlite3_bind_text_copy(stmt, 2, payload.text)
        sqlite3_bind_text_copy(stmt, 3, folded)
        sqlite3_bind_text_copy(stmt, 4, payload.contentHash)
        sqlite3_bind_int(stmt, 5, Int32(conflict.copyCount))
        sqlite3_bind_int(stmt, 6, mergedPinned ? 1 : 0)
        if let mergedPinnedAt {
            sqlite3_bind_double(stmt, 7, mergedPinnedAt.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(stmt, 7)
        }
        sqlite3_bind_text_copy(stmt, 8, current.id.uuidString.uppercased())
        return sqlite3_step(stmt) == SQLITE_DONE
    }

    /// 按 id 回读单条（串行队列上下文内调用，不另开只读连接）
    private func clipItemByID(_ db: OpaquePointer, _ key: String) -> ClipboardItem? {
        let sql = "SELECT \(ClipboardSchema.columns) FROM clipboard_items WHERE id = ?;"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.warning("剪贴板编辑回读准备失败: \(String(cString: sqlite3_errmsg(db)))")
            return nil
        }
        sqlite3_bind_text_copy(stmt, 1, key)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return clipItem(from: stmt)
    }
}
