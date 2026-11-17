import Foundation
import SQLite3
import NetworkMonitorCore

// MARK: - 剪贴板 schema 版本阶梯

/// 版本阶梯的对外契约：迁移后版本 == 当前最新 · 重复迁移幂等 · 高版本不被低版本段写回 ·
/// 低版本可重放升级；列定义（列名 / 列串 / 行映射下标）三者同源不串位。
func runClipboardSchemaLadderTests() {
    print("🧪 Testing 剪贴板 schema 版本阶梯...")

    // 正常路径：迁移后版本停在当前最新，表与两条索引就位
    do {
        let db = DatabaseManager()
        db.initializeInMemory()
        defer { db.close() }
        assertEqual(currentVersion(db), Int(ClipboardSchema.latestVersion), "迁移后 user_version == 当前最新")
        assertEqual(collectQuery(db, sql: "SELECT name FROM sqlite_master WHERE type='table' AND name='clipboard_items'").count, 1, "剪贴板表已创建")
        assertEqual(collectQuery(db, sql: "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_clipboard_order'").count, 1, "排序索引已创建")
        // 幂等：重复迁移不改版本（v1 / v2 段不重跑、也不把版本写回低位）
        db.migrateIfNeeded()
        db.migrateIfNeeded()
        assertEqual(currentVersion(db), Int(ClipboardSchema.latestVersion), "重复迁移幂等，版本不变")
    }

    // 边界 1：库已被更高版本迁移过时，低版本段不得把版本写回
    do {
        let db = DatabaseManager()
        db.initializeInMemory()
        defer { db.close() }
        let future = Int(ClipboardSchema.latestVersion) + 1
        db.query(sql: "PRAGMA user_version = \(future)") { _ in }
        db.migrateIfNeeded()
        assertEqual(currentVersion(db), future, "高版本库不被低版本段写回")
    }

    // 边界 2：版本回退到 0 后可整段重放，重新升到当前最新
    do {
        let db = DatabaseManager()
        db.initializeInMemory()
        defer { db.close() }
        db.query(sql: "PRAGMA user_version = 0") { _ in }
        db.migrateIfNeeded()
        assertEqual(currentVersion(db), Int(ClipboardSchema.latestVersion), "版本回退后可重放升到最新")
    }

    // 列定义自检：表列顺序、SELECT 列串、行映射下标三者必须一一对应
    do {
        let db = DatabaseManager()
        db.initializeInMemory()
        defer { db.close() }
        let tableColumns = collectQuery(db, sql: "PRAGMA table_info(clipboard_items)").compactMap { $0[1] }
        assertEqual(tableColumns, ClipboardSchema.columnNames, "表列顺序与列名数组一致")
        assertEqual(ClipboardSchema.columns.components(separatedBy: ", "), ClipboardSchema.columnNames, "SELECT 列串与列名数组一致")
        assertEqual(ClipboardSchema.Column.allCases.count, tableColumns.count, "列数 == TableInfo 列数 == 下标最大值 + 1")
        assertEqual(Set(ClipboardSchema.Column.allCases.map(\.index)).count, tableColumns.count, "每个列下标唯一")
    }

    // 列序不错位：写入含全部字段的条目，读回逐字段比对
    do {
        let db = DatabaseManager()
        db.initializeInMemory()
        defer { db.close() }
        let createdAt = Date(timeIntervalSince1970: 1_700_000_123.5)
        guard let saved = db.saveClipboardItem(ClipboardDraft(kind: .image, contentHash: "hash-ladder-full",
                                                             text: "正文-占位",
                                                             preview: "摘要-占位",
                                                             imagePath: "/tmp/ladder.png",
                                                             imageWidth: 640, imageHeight: 480,
                                                             sourceBundleID: "com.apple.Safari",
                                                             sourceAppName: "Safari",
                                                             createdAt: createdAt)) else {
            assertEqual(false, true, "全字段条目插入失败")
            return
        }
        _ = db.setClipboardItemPinned(id: saved.id, isPinned: true)
        db.updateClipboardStackPositions([saved.id])
        // OCR 列：识别结果走独立协议回写（v3 新增列，列序错位会在这条断言上暴露）
        _ = db.updateClipboardItemOCRText(id: saved.id, text: "识别出的文字")

        guard let back = db.fetchClipboardItem(id: saved.id) else {
            assertEqual(false, true, "全字段条目回读失败")
            return
        }
        assertEqual(back.id, saved.id, "id 不错位")
        assertEqual(back.kind, .image, "kind 不错位")
        assertEqual(back.text, "正文-占位", "text 不错位")
        assertEqual(back.preview, "摘要-占位", "preview 不错位")
        assertEqual(back.imagePath, "/tmp/ladder.png", "image_path 不错位")
        assertEqual(back.imageWidth, 640, "image_width 不错位")
        assertEqual(back.imageHeight, 480, "image_height 不错位")
        assertEqual(back.contentHash, "hash-ladder-full", "content_hash 不错位")
        assertEqual(back.sourceBundleID, "com.apple.Safari", "source_bundle_id 不错位")
        assertEqual(back.sourceAppName, "Safari", "source_app_name 不错位")
        assertEqual(back.copyCount, 1, "copy_count 不错位")
        assertEqual(back.isPinned, true, "is_pinned 不错位")
        assertEqual(back.createdAt.timeIntervalSince1970, createdAt.timeIntervalSince1970, "created_at 不错位")
        assertNotNil(back.pinnedAt, "pinned_at 不错位")
        assertEqual(back.stackPosition, 1, "stack_position 不错位")
        assertEqual(back.ocrText, "识别出的文字", "ocr_text 不错位")
        assertEqual(back, db.fetchAllClipboardItems(kind: nil).first, "全量查询与按 id 回读同一行同一列序")
    }

    // 异常：kind 不在枚举里的历史行被跳过（不崩、不串列），其余行照常读出
    do {
        let db = DatabaseManager()
        db.initializeInMemory()
        defer { db.close() }
        _ = db.saveClipboardItem(ClipboardDraft(kind: .text, contentHash: "hash-ladder-ok", text: "正常行"))
        db.query(sql: """
            INSERT INTO clipboard_items (id, kind, preview, content_hash, created_at)
            VALUES ('11111111-2222-3333-4444-555555555555', 'mystery', '未知类型', 'hash-ladder-unknown', 0);
            """) { _ in }
        let items = db.fetchAllClipboardItems(kind: nil)
        assertEqual(items.count, 1, "未识别 kind 的行被跳过")
        assertEqual(items.first?.contentHash, "hash-ladder-ok", "跳过的不是正常行")
    }

    print("✅ 剪贴板 schema 版本阶梯 works")
}

/// 读 PRAGMA user_version 为 Int（feature 值）
private func currentVersion(_ db: DatabaseManager) -> Int {
    var version = -1
    db.query(sql: "PRAGMA user_version") { version = Int(sqlite3_column_int($0, 0)) }
    return version
}
