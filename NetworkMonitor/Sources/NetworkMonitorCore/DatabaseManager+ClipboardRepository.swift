import Foundation
import SQLite3

// MARK: - 剪贴板仓储实现

/// DatabaseManager 的剪贴板仓储实现（接口隔离：见 ClipboardRepository）
///
/// 线程模型：所有方法经 DatabaseManager 的 serialQueue 同步执行，与 Hook / Token 写入共享同一队列；
/// 行映射与绑定辅助见 DatabaseManager+ClipboardSchema.swift。
/// - Warning: 不得在 query(sql:handler:) 的回调内或串行队列上下文内调用本扩展的方法，否则死锁。
extension DatabaseManager: ClipboardRepository {

    // MARK: - 写入

    public func saveClipboardItem(_ draft: ClipboardDraft) -> ClipboardItem? {
        guard !draft.contentHash.isEmpty else {
            logger.debug("剪贴板内容哈希为空，跳过落库")
            return nil
        }
        // 摘要口径统一由 Core 生成，调用方只在图片 / 文件等类型显式提供
        let preview = draft.preview ?? ClipboardPreview.make(from: draft.text ?? "")
        let newID = UUID().uuidString

        return serialQueue.sync { () -> ClipboardItem? in
            guard let db else {
                logger.debug("数据库未就绪，剪贴板条目未落库")
                return nil
            }
            // 单条原子 upsert：命中 content_hash 时保留原 id，仅自增 copy_count 并刷新时间与来源
            let sql = """
            INSERT INTO clipboard_items
                (id, kind, text, preview, image_path, image_width, image_height,
                 content_hash, source_bundle_id, source_app_name, copy_count, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?)
            ON CONFLICT(content_hash) DO UPDATE SET
                copy_count = copy_count + 1, created_at = excluded.created_at,
                source_bundle_id = excluded.source_bundle_id, source_app_name = excluded.source_app_name;
            """
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                logger.warning("剪贴板写入准备失败: \(String(cString: sqlite3_errmsg(db)))")
                return nil
            }
            sqlite3_bind_text(stmt, 1, (newID as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (draft.kind.rawValue as NSString).utf8String, -1, nil)
            sqlite3_bind_text_or_null(stmt, 3, draft.text)
            sqlite3_bind_text(stmt, 4, (preview as NSString).utf8String, -1, nil)
            sqlite3_bind_text_or_null(stmt, 5, draft.imagePath)
            clipBindIntOrNull(stmt, 6, draft.imageWidth)
            clipBindIntOrNull(stmt, 7, draft.imageHeight)
            sqlite3_bind_text(stmt, 8, (draft.contentHash as NSString).utf8String, -1, nil)
            sqlite3_bind_text_or_null(stmt, 9, draft.sourceBundleID)
            sqlite3_bind_text_or_null(stmt, 10, draft.sourceAppName)
            sqlite3_bind_double(stmt, 11, draft.createdAt.timeIntervalSince1970)

            guard sqlite3_step(stmt) == SQLITE_DONE else {
                logger.warning("剪贴板写入失败: \(String(cString: sqlite3_errmsg(db)))")
                return nil
            }
            return clipItemByHash(db, draft.contentHash)
        }
    }

    // MARK: - 查询

    public func fetchClipboardItem(id: UUID) -> ClipboardItem? {
        let key = id.uuidString.uppercased()
        return serialQueue.sync { () -> ClipboardItem? in
            guard let db else { return nil }
            let sql = "SELECT \(ClipboardSchema.columns) FROM clipboard_items WHERE id = ?;"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                logger.warning("剪贴板查询准备失败: \(String(cString: sqlite3_errmsg(db)))")
                return nil
            }
            sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, nil)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return clipItem(from: stmt)
        }
    }

    public func fetchClipboardItems(kind: ClipboardItemKind?, limit: Int) -> [ClipboardItem] {
        guard limit > 0 else { return [] }
        return serialQueue.sync { () -> [ClipboardItem] in
            guard let db else { return [] }
            var sql = "SELECT \(ClipboardSchema.columns) FROM clipboard_items"
            if kind != nil { sql += " WHERE kind = ?" }
            sql += " ORDER BY is_pinned DESC, created_at DESC LIMIT ?;"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                logger.warning("剪贴板查询准备失败: \(String(cString: sqlite3_errmsg(db)))")
                return []
            }
            var index: Int32 = 1
            if let kind {
                sqlite3_bind_text(stmt, index, (kind.rawValue as NSString).utf8String, -1, nil)
                index += 1
            }
            sqlite3_bind_int(stmt, index, Int32(limit))
            return clipItems(from: stmt)
        }
    }

    public func fetchAllClipboardItems(kind: ClipboardItemKind?) -> [ClipboardItem] {
        serialQueue.sync { () -> [ClipboardItem] in
            guard let db else { return [] }
            var sql = "SELECT \(ClipboardSchema.columns) FROM clipboard_items"
            if kind != nil { sql += " WHERE kind = ?" }
            sql += " ORDER BY is_pinned DESC, created_at DESC;"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                logger.warning("剪贴板全量查询准备失败: \(String(cString: sqlite3_errmsg(db)))")
                return []
            }
            if let kind {
                sqlite3_bind_text(stmt, 1, (kind.rawValue as NSString).utf8String, -1, nil)
            }
            return clipItems(from: stmt)
        }
    }

    public func fetchClipboardStack() -> [ClipboardItem] {
        serialQueue.sync { () -> [ClipboardItem] in
            guard let db else { return [] }
            let sql = """
            SELECT \(ClipboardSchema.columns) FROM clipboard_items
            WHERE stack_position IS NOT NULL ORDER BY stack_position ASC;
            """
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                logger.warning("剪贴板栈查询准备失败: \(String(cString: sqlite3_errmsg(db)))")
                return []
            }
            return clipItems(from: stmt)
        }
    }

    public func clipboardItemCount() -> Int {
        serialQueue.sync { () -> Int in
            guard let db else { return 0 }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM clipboard_items;", -1, &stmt, nil) == SQLITE_OK,
                  sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
            return Int(sqlite3_column_int(stmt, 0))
        }
    }

    // MARK: - 收藏 / 删除 / 清空

    public func setClipboardItemPinned(id: UUID, isPinned: Bool) -> Bool {
        let key = id.uuidString.uppercased()
        return serialQueue.sync { () -> Bool in
            guard let db else { return false }
            let sql = "UPDATE clipboard_items SET is_pinned = ?, pinned_at = ? WHERE id = ?;"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                logger.warning("剪贴板收藏更新准备失败: \(String(cString: sqlite3_errmsg(db)))")
                return false
            }
            sqlite3_bind_int(stmt, 1, isPinned ? 1 : 0)
            if isPinned {
                sqlite3_bind_double(stmt, 2, Date().timeIntervalSince1970)
            } else {
                sqlite3_bind_null(stmt, 2)
            }
            sqlite3_bind_text(stmt, 3, (key as NSString).utf8String, -1, nil)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                logger.warning("剪贴板收藏更新失败: \(String(cString: sqlite3_errmsg(db)))")
                return false
            }
            return sqlite3_changes(db) > 0
        }
    }

    public func deleteClipboardItem(id: UUID) -> Bool {
        let key = id.uuidString.uppercased()
        return serialQueue.sync { () -> Bool in
            guard let db else { return false }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, "DELETE FROM clipboard_items WHERE id = ?;", -1, &stmt, nil) == SQLITE_OK else {
                logger.warning("剪贴板删除准备失败: \(String(cString: sqlite3_errmsg(db)))")
                return false
            }
            sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, nil)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                logger.warning("剪贴板删除失败: \(String(cString: sqlite3_errmsg(db)))")
                return false
            }
            return sqlite3_changes(db) > 0
        }
    }

    public func clearClipboardItems(keepingPinned: Bool) -> Int {
        serialQueue.sync { () -> Int in
            guard let db else { return 0 }
            let sql = keepingPinned
                ? "DELETE FROM clipboard_items WHERE is_pinned = 0;"
                : "DELETE FROM clipboard_items;"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
                  sqlite3_step(stmt) == SQLITE_DONE else {
                logger.warning("剪贴板清空失败: \(String(cString: sqlite3_errmsg(db)))")
                return 0
            }
            return Int(sqlite3_changes(db))
        }
    }

    public func updateClipboardStackPositions(_ orderedIDs: [UUID]) {
        serialQueue.sync { () -> Void in
            guard let db else { return }
            // 整体在单事务内完成：中途失败则回滚，避免留下半截编号
            guard clipExec(db, "BEGIN") else {
                logger.warning("剪贴板栈重排事务开启失败: \(String(cString: sqlite3_errmsg(db)))")
                return
            }
            guard clipExec(db, "UPDATE clipboard_items SET stack_position = NULL;") else {
                clipExec(db, "ROLLBACK")
                logger.warning("剪贴板栈清空失败: \(String(cString: sqlite3_errmsg(db)))")
                return
            }
            let sql = "UPDATE clipboard_items SET stack_position = ? WHERE id = ?;"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                clipExec(db, "ROLLBACK")
                logger.warning("剪贴板栈重排准备失败: \(String(cString: sqlite3_errmsg(db)))")
                return
            }
            for (offset, id) in orderedIDs.enumerated() {
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)
                sqlite3_bind_int(stmt, 1, Int32(offset + 1))
                sqlite3_bind_text(stmt, 2, (id.uuidString.uppercased() as NSString).utf8String, -1, nil)
                guard sqlite3_step(stmt) == SQLITE_DONE else {
                    clipExec(db, "ROLLBACK")
                    logger.warning("剪贴板栈重排失败: \(String(cString: sqlite3_errmsg(db)))")
                    return
                }
            }
            if !clipExec(db, "COMMIT") {
                clipExec(db, "ROLLBACK")
                logger.warning("剪贴板栈重排提交失败: \(String(cString: sqlite3_errmsg(db)))")
            }
        }
    }

    // MARK: - 超限清理

    public func pruneClipboardItems(maxItems: Int, retentionDays: Int) -> Int {
        let limit = maxItems > 0 ? maxItems : ClipboardLimit.defaultMaxItems
        let days = retentionDays > 0 ? retentionDays : ClipboardLimit.defaultRetentionDays

        return serialQueue.sync { () -> Int in
            guard let db else { return 0 }
            var deleted = 0

            // 1) 保留天数：早于截止时间的非收藏项（收藏豁免）
            let cutoff = Date().addingTimeInterval(-Double(days) * 86_400).timeIntervalSince1970
            var expireStmt: OpaquePointer?
            defer { sqlite3_finalize(expireStmt) }
            let expireSQL = "DELETE FROM clipboard_items WHERE is_pinned = 0 AND created_at < ?;"
            if sqlite3_prepare_v2(db, expireSQL, -1, &expireStmt, nil) == SQLITE_OK {
                sqlite3_bind_double(expireStmt, 1, cutoff)
                if sqlite3_step(expireStmt) == SQLITE_DONE {
                    deleted += Int(sqlite3_changes(db))
                } else {
                    logger.warning("剪贴板过期清理失败: \(String(cString: sqlite3_errmsg(db)))")
                }
            }

            // 2) 条数上限：非收藏项按创建时间倒序保留前 limit 条（收藏不占额度）
            let countSQL = """
            DELETE FROM clipboard_items
            WHERE is_pinned = 0 AND id NOT IN (
                SELECT id FROM clipboard_items WHERE is_pinned = 0
                ORDER BY created_at DESC LIMIT ?
            );
            """
            var countStmt: OpaquePointer?
            defer { sqlite3_finalize(countStmt) }
            if sqlite3_prepare_v2(db, countSQL, -1, &countStmt, nil) == SQLITE_OK {
                sqlite3_bind_int(countStmt, 1, Int32(limit))
                if sqlite3_step(countStmt) == SQLITE_DONE {
                    deleted += Int(sqlite3_changes(db))
                } else {
                    logger.warning("剪贴板超限清理失败: \(String(cString: sqlite3_errmsg(db)))")
                }
            }
            return deleted
        }
    }
}
