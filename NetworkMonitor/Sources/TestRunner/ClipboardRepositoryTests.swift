import Foundation
import SQLite3
import NetworkMonitorCore

// MARK: - 剪贴板仓储与未初始化容错（从 main.swift 拆出）

// Helper: run query on DatabaseManager and collect results as rows of [String?]
func collectQuery(_ db: DatabaseManager, sql: String) -> [[String?]] {
    var rows: [[String?]] = []
    db.query(sql: sql) { stmt in
        var row: [String?] = []
        let colCount = sqlite3_column_count(stmt)
        for i in 0..<colCount {
            if sqlite3_column_type(stmt, i) == SQLITE_NULL {
                row.append(nil)
            } else if let cStr = sqlite3_column_text(stmt, i) {
                row.append(String(cString: cStr))
            } else {
                row.append(nil)
            }
        }
        rows.append(row)
    }
    return rows
}

// MARK: - 剪贴板仓储（SQLite）

func runClipboardRepositoryTests() {
    print("🧪 Testing ClipboardRepository (SQLite)...")
    do {
        let db = DatabaseManager()
        db.initializeInMemory()
        defer { db.close() }

        // 建表与迁移：user_version 1 → 2
        var version = -1
        db.query(sql: "PRAGMA user_version") { version = Int(sqlite3_column_int($0, 0)) }
        assertEqual(version, 2, "user_version 迁移到 2")
        assertEqual(collectQuery(db, sql: "SELECT name FROM sqlite_master WHERE type='table' AND name='clipboard_items'").count, 1, "剪贴板表已创建")
        assertEqual(collectQuery(db, sql: "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_clipboard_content_hash'").count, 1, "内容哈希唯一索引已创建")
        db.migrateIfNeeded()
        db.migrateIfNeeded()
        db.query(sql: "PRAGMA user_version") { version = Int(sqlite3_column_int($0, 0)) }
        assertEqual(version, 2, "重复迁移幂等（user_version 仍为 2）")
        assertEqual(collectQuery(db, sql: "SELECT COUNT(*) FROM clipboard_items").count, 1, "重复迁移不重复建表")

        // 插入
        let first = db.saveClipboardItem(ClipboardDraft(kind: .text, contentHash: "hash-1", text: "hello\nworld",
                                                       sourceBundleID: "com.apple.Safari", sourceAppName: "Safari"))
        assertNotNil(first, "首条插入成功")
        assertEqual(first?.copyCount, 1, "新条目 copy_count 从 1 起")
        assertEqual(first?.preview, "hello world", "摘要由 Core 自动生成（折叠换行）")
        assertEqual(first?.kind, .text, "类型正确")
        let firstID = first?.id

        // 去重：同哈希再插入 → id 不变 + copy_count 自增 + 来源刷新 + 时间置顶
        let later = Date().addingTimeInterval(60)
        let second = db.saveClipboardItem(ClipboardDraft(kind: .text, contentHash: "hash-1", text: "hello\nworld",
                                                        sourceBundleID: "com.google.Chrome", sourceAppName: "Chrome",
                                                        createdAt: later))
        assertEqual(second?.id, firstID, "命中去重保留原 id")
        assertEqual(second?.copyCount, 2, "命中去重 copy_count 自增为 2")
        assertEqual(second?.sourceAppName, "Chrome", "命中去重刷新来源 App")
        assertEqual(second?.createdAt.timeIntervalSince1970, later.timeIntervalSince1970, "命中去重刷新创建时间")
        assertEqual(db.clipboardItemCount(), 1, "去重后仍只有 1 条记录")

        // 无效入参：空哈希不落库
        assertEqual(db.saveClipboardItem(ClipboardDraft(kind: .text, contentHash: "", text: "无效")) == nil, true, "空内容哈希不落库")
        assertEqual(db.clipboardItemCount(), 1, "空哈希未产生新记录")

        // 图片条目
        assertNotNil(db.saveClipboardItem(ClipboardDraft(kind: .image, contentHash: "hash-2", preview: "图片 100×50",
                                                         imagePath: "/tmp/clip.png", imageWidth: 100, imageHeight: 50)),
                     "图片条目插入成功")
        assertEqual(db.fetchClipboardItems(kind: nil, limit: 10).count, 2, "分页查询全部 2 条")
        assertEqual(db.fetchClipboardItems(kind: .image, limit: 10).count, 1, "按类型过滤 1 条")
        assertEqual(db.fetchClipboardItems(kind: nil, limit: 0).count, 0, "limit=0 归一化为空结果")
        assertEqual(db.fetchClipboardItems(kind: nil, limit: -5).count, 0, "负 limit 归一化为空结果")
        assertEqual(db.fetchAllClipboardItems(kind: nil).count, 2, "全量查询 2 条")
        if let imageID = db.fetchClipboardItems(kind: .image, limit: 1).first?.id {
            let fetched = db.fetchClipboardItem(id: imageID)
            assertEqual(fetched?.kind, .image, "按 id 回读类型")
            assertEqual(fetched?.imageWidth, 100, "按 id 回读图片宽度")
            assertEqual(fetched?.imageHeight, 50, "按 id 回读图片高度")
            assertEqual(fetched?.isPinned, false, "默认未收藏")
        }
        assertEqual(db.fetchClipboardItem(id: UUID()) == nil, true, "查询不存在的 id 返回 nil")

        // 收藏（收藏即置顶，豁免清理）
        if let firstID {
            assertEqual(db.setClipboardItemPinned(id: firstID, isPinned: true), true, "收藏成功")
            let ordered = db.fetchAllClipboardItems(kind: nil)
            assertEqual(ordered.first?.id, firstID, "收藏项排在最前")
            assertEqual(ordered.first?.pinnedAt != nil, true, "收藏时间已写入")
            assertEqual(db.setClipboardItemPinned(id: firstID, isPinned: false), true, "取消收藏成功")
            assertEqual(db.fetchClipboardItem(id: firstID)?.pinnedAt == nil, true, "取消收藏清空收藏时间")
        }
        assertEqual(db.setClipboardItemPinned(id: UUID(), isPinned: true), false, "收藏不存在的 id 返回 false")

        // 清空：保留收藏
        if let firstID {
            _ = db.setClipboardItemPinned(id: firstID, isPinned: true)
        }
        assertEqual(db.clearClipboardItems(keepingPinned: true), 1, "清空删除 1 条非收藏")
        assertEqual(db.clipboardItemCount(), 1, "清空后仅剩收藏项")
        assertEqual(db.clearClipboardItems(keepingPinned: false), 1, "全清删除收藏项")
        assertEqual(db.clipboardItemCount(), 0, "全部清空")

        // 删除单条
        let doomed = db.saveClipboardItem(ClipboardDraft(kind: .text, contentHash: "hash-3", text: "del-me"))
        assertNotNil(doomed, "删除测试条目插入成功")
        if let doomed {
            assertEqual(db.deleteClipboardItem(id: doomed.id), true, "删除单条成功")
        }
        assertEqual(db.deleteClipboardItem(id: UUID()), false, "删除不存在的 id 返回 false")
        assertEqual(db.clipboardItemCount(), 0, "删除后计数为 0")

        print("✅ ClipboardRepository 建表 / 迁移 / 去重 / 收藏 / 删除 / 清空 works")
    }

}

// MARK: - 剪贴板数据库未初始化容错

func runClipboardUninitializedTests() {
    do {
        let db = DatabaseManager()
        assertEqual(db.isReady, false, "数据库未初始化")
        assertEqual(db.saveClipboardItem(ClipboardDraft(kind: .text, contentHash: "x", text: "x")) == nil, true, "未初始化时不写入")
        assertEqual(db.fetchClipboardItem(id: UUID()) == nil, true, "未初始化时按 id 查询返回 nil")
        assertEqual(db.fetchClipboardItems(kind: nil, limit: 10).isEmpty, true, "未初始化时分页查询返回空")
        assertEqual(db.fetchAllClipboardItems(kind: nil).isEmpty, true, "未初始化时全量查询返回空")
        assertEqual(db.setClipboardItemPinned(id: UUID(), isPinned: true), false, "未初始化时收藏返回 false")
        assertEqual(db.deleteClipboardItem(id: UUID()), false, "未初始化时删除返回 false")
        assertEqual(db.clearClipboardItems(keepingPinned: true), 0, "未初始化时清空返回 0")
        assertEqual(db.pruneClipboardItems(maxItems: 1, retentionDays: 1), 0, "未初始化时清理返回 0")
        assertEqual(db.clipboardItemCount(), 0, "未初始化时计数为 0")
        assertEqual(db.searchClipboardItems(query: "任意", limit: 10).isEmpty, true, "未初始化时全文检索返回空")
        assertEqual(db.searchClipboardItems(query: "任意", limit: Int.max).isEmpty, true, "未初始化时全文检索极大 limit 仍为空")
        db.updateClipboardStackPositions([UUID()])
        assertEqual(db.fetchClipboardStack().isEmpty, true, "未初始化时栈为空")
        print("✅ Clipboard 数据库未初始化容错 works")
    }

}

