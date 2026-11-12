import Foundation
import SQLite3

// MARK: - 剪贴板仓储实现

/// DatabaseManager 的剪贴板仓储实现（接口隔离：见 ClipboardRepository）
/// 线程模型：经 serialQueue 同步执行；行映射辅助见 DatabaseManager+ClipboardSchema.swift。
/// - Warning: 不得在 query(sql:handler:) 回调内或串行队列上下文调用，否则死锁。
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
            sqlite3_bind_text_copy(stmt, 1, newID)
            sqlite3_bind_text_copy(stmt, 2, draft.kind.rawValue)
            sqlite3_bind_text_or_null(stmt, 3, draft.text)
            sqlite3_bind_text_copy(stmt, 4, preview)
            sqlite3_bind_text_or_null(stmt, 5, draft.imagePath)
            clipBindIntOrNull(stmt, 6, draft.imageWidth)
            clipBindIntOrNull(stmt, 7, draft.imageHeight)
            sqlite3_bind_text_copy(stmt, 8, draft.contentHash)
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
            sqlite3_bind_text_copy(stmt, 1, key)
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
                sqlite3_bind_text_copy(stmt, index, kind.rawValue)
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
                sqlite3_bind_text_copy(stmt, 1, kind.rawValue)
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
            sqlite3_bind_text_copy(stmt, 3, key)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                logger.warning("剪贴板收藏更新失败: \(String(cString: sqlite3_errmsg(db)))")
                return false
            }
            return sqlite3_changes(db) > 0
        }
    }

    public func deleteClipboardItem(id: UUID) -> ClipboardItem? {
        let key = id.uuidString.uppercased()
        return serialQueue.sync { () -> ClipboardItem? in
            guard let db else { return nil }
            // 返回被删条目（而不是 Bool）：上层据此回收该条的落盘原图与缩略图
            let doomed = clipDeleteBatch(db,
                                         selectSQL: "SELECT \(ClipboardSchema.columns) FROM clipboard_items WHERE id = ?;",
                                         deleteSQL: "DELETE FROM clipboard_items WHERE id = ?;",
                                         failureLabel: "剪贴板删除",
                                         bind: { sqlite3_bind_text_copy($0, 1, key) })
            return doomed?.first
        }
    }

    public func clearClipboardItems(keepingPinned: Bool) -> [ClipboardItem] {
        serialQueue.sync { () -> [ClipboardItem] in
            guard let db else { return [] }
            let whereClause = keepingPinned ? " WHERE is_pinned = 0" : ""
            return clipDeleteBatch(db,
                                   selectSQL: "SELECT \(ClipboardSchema.columns) FROM clipboard_items\(whereClause);",
                                   deleteSQL: "DELETE FROM clipboard_items\(whereClause);",
                                   failureLabel: "剪贴板清空",
                                   bind: { _ in }) ?? []
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
                sqlite3_bind_text_copy(stmt, 2, id.uuidString.uppercased())
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

    public func pruneClipboardItems(maxItems: Int, retentionDays: Int) -> [ClipboardItem] {
        let limit = maxItems > 0 ? maxItems : ClipboardLimit.defaultMaxItems
        let days = retentionDays > 0 ? retentionDays : ClipboardLimit.defaultRetentionDays

        return serialQueue.sync { () -> [ClipboardItem] in
            guard let db else { return [] }
            var deleted: [ClipboardItem] = []

            // 1) 保留天数：早于截止时间的非收藏项（收藏豁免）
            let cutoff = Date().addingTimeInterval(-Double(days) * 86_400).timeIntervalSince1970
            if let expired = clipDeleteBatch(db,
                                             selectSQL: "SELECT \(ClipboardSchema.columns) FROM clipboard_items WHERE is_pinned = 0 AND created_at < ?;",
                                             deleteSQL: "DELETE FROM clipboard_items WHERE is_pinned = 0 AND created_at < ?;",
                                             failureLabel: "剪贴板过期清理",
                                             bind: { sqlite3_bind_double($0, 1, cutoff) }) {
                deleted.append(contentsOf: expired)
            }

            // 2) 条数上限：非收藏项按创建时间倒序保留前 limit 条（收藏不占额度）
            let overflowWhere = " WHERE is_pinned = 0 AND id NOT IN (SELECT id FROM clipboard_items"
                + " WHERE is_pinned = 0 ORDER BY created_at DESC LIMIT ?)"
            if let overflow = clipDeleteBatch(db,
                                              selectSQL: "SELECT \(ClipboardSchema.columns) FROM clipboard_items\(overflowWhere) ORDER BY created_at DESC;",
                                              deleteSQL: "DELETE FROM clipboard_items\(overflowWhere);",
                                              failureLabel: "剪贴板超限清理",
                                              bind: { sqlite3_bind_int($0, 1, Int32(limit)) }) {
                deleted.append(contentsOf: overflow)
            }
            return deleted
        }
    }
}

// MARK: - 批量删除共用辅助

extension DatabaseManager {

    /// 「先取被删行、再删行」单事务 —— 三条删除接口共用（selectSQL 的 WHERE 必须与 deleteSQL 一致）
    func clipDeleteBatch(_ db: OpaquePointer, selectSQL: String, deleteSQL: String,
                         failureLabel: String, bind: (OpaquePointer?) -> Void) -> [ClipboardItem]? {
        guard clipExec(db, "BEGIN") else { return clipBatchFail(db, failureLabel, "事务开启失败") }
        var doomedStmt: OpaquePointer?
        defer { sqlite3_finalize(doomedStmt) }
        guard sqlite3_prepare_v2(db, selectSQL, -1, &doomedStmt, nil) == SQLITE_OK else {
            return clipBatchFail(db, failureLabel, "待删行查询准备失败")
        }
        bind(doomedStmt)
        let doomed = clipItems(from: doomedStmt)
        var deleteStmt: OpaquePointer?
        defer { sqlite3_finalize(deleteStmt) }
        guard sqlite3_prepare_v2(db, deleteSQL, -1, &deleteStmt, nil) == SQLITE_OK else {
            return clipBatchFail(db, failureLabel, "准备失败")
        }
        bind(deleteStmt)
        guard sqlite3_step(deleteStmt) == SQLITE_DONE else { return clipBatchFail(db, failureLabel, "失败") }
        guard clipExec(db, "COMMIT") else { return clipBatchFail(db, failureLabel, "提交失败") }
        return doomed
    }

    /// 回滚 + 一行 warning（失败标签区分操作，不带路径）
    private func clipBatchFail(_ db: OpaquePointer, _ label: String, _ reason: String) -> [ClipboardItem]? {
        _ = clipExec(db, "ROLLBACK")
        logger.warning("\(label)\(reason): \(String(cString: sqlite3_errmsg(db)))")
        return nil
    }
}
