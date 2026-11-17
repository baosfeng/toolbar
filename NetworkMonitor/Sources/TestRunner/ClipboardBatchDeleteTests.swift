import Foundation
import NetworkMonitorCore

// MARK: - 剪贴板批量删除（多选删除的存储口径）

/// 批量删除的守卫：命中集合删、未命中静默忽略、空集合不写、返回被删行供回收图片
func runClipboardBatchDeleteTests() {
    print("🧪 Testing clipboard batch delete...")
    do {
        let db = DatabaseManager()
        db.initializeInMemory()
        defer { db.close() }

        let a = db.saveClipboardItem(ClipboardDraft(kind: .text, contentHash: "batch-1", text: "第一条"))
        let b = db.saveClipboardItem(ClipboardDraft(kind: .text, contentHash: "batch-2", text: "第二条"))
        let c = db.saveClipboardItem(ClipboardDraft(kind: .text, contentHash: "batch-3", text: "第三条"))
        assertNotNil(a, "批量删除：第一条已落库")
        assertNotNil(b, "批量删除：第二条已落库")
        assertNotNil(c, "批量删除：第三条已落库")
        assertEqual(db.clipboardItemCount(), 3, "批量删除：初始 3 条")

        // 空集合：不做任何写入
        assertEqual(db.deleteClipboardItems(ids: []).isEmpty, true, "空集合不删任何条目")
        assertEqual(db.clipboardItemCount(), 3, "空集合后条数不变")

        // 命中两条：返回被删行（供上层回收图片）
        let doomed = db.deleteClipboardItems(ids: Set([a!.id, c!.id]))
        assertEqual(doomed.count, 2, "命中两条返回两条被删记录")
        assertEqual(Set(doomed.map(\.id)), Set([a!.id, c!.id]), "返回的正是被选中的那两条")
        assertEqual(db.clipboardItemCount(), 1, "批量删除后只剩 1 条")
        assertEqual(db.fetchClipboardItem(id: b!.id)?.id, b!.id, "未选中的条目仍在库里")
        assertEqual(db.fetchClipboardItem(id: a!.id) == nil, true, "被删条目已不可读")

        // 混入不存在的 id：静默忽略，不报错也不多删
        let mixed = db.deleteClipboardItems(ids: Set([b!.id, UUID()]))
        assertEqual(mixed.count, 1, "不存在的 id 被忽略，只删命中那条")
        assertEqual(db.clipboardItemCount(), 0, "全部删完后库里为空")

        // 重复删除同一条：第二次返回空（幂等，不抛错）
        assertEqual(db.deleteClipboardItems(ids: Set([b!.id])).isEmpty, true, "重复删除同一 id 返回空")

        print("✅ Clipboard 批量删除 works")
    }
}
