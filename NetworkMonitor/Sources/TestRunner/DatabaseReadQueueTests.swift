import Foundation
import NetworkMonitorCore

// MARK: - 读写分队列：独立只读连接的可见性

/// 文件库（WAL）+ 独立只读连接：
/// - 写入后**立即**能读到（不依赖 checkpoint 时机）
/// - 连续读写交替仍读得到新数据（只读连接没有把快照钉死在第一次读）
/// - 内存库拿不到第二个连接 → 只读查询退化为写队列，语义不变
func runDatabaseReadQueueTests() {
    print("🧪 Testing 读写分队列（只读连接可见性）...")
    let dir = NSTemporaryDirectory() + "nm-db-read-" + UUID().uuidString
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: dir) }

    let db = DatabaseManager(path: dir + "/monitor.db")
    db.initialize()
    defer { db.close() }
    assertEqual(db.isReady, true, "文件库已就绪")
    assertEqual(db.isUsingDedicatedReadConnection, true, "文件库应启用独立只读连接")

    // 1) 剪贴板：写入 → 立即只读读到（同一毫秒内，不等 checkpoint）
    let item = db.saveClipboardItem(ClipboardDraft(kind: .text, contentHash: "hash-read-1", text: "只读可见"))
    assertNotNil(item, "写入成功")
    assertEqual(db.fetchClipboardItems(kind: nil, limit: 5).count, 1, "写入后立即读到 1 条")

    // 2) 再写一轮：只读连接不会停在第一次读的快照上
    _ = db.saveClipboardItem(ClipboardDraft(kind: .text, contentHash: "hash-read-2", text: "第二条"))
    assertEqual(db.fetchClipboardItems(kind: nil, limit: 5).count, 2, "第二轮写入后读到 2 条")
    assertEqual(db.clipboardItemCount(), 2, "只读路径计数一致")
    assertEqual(db.searchClipboardItems(query: "第二条", limit: 5).count, 1, "全文检索走只读连接且命中")

    // 3) Token 表：写入 → 聚合（聚合整条链路都走只读连接）
    let record = HarnessSessionScanRecord(path: dir + "/s/1.jsonl", sessionID: "s1",
                                          size: 10, mtimeMs: 20, scannedAt: 30)
    let event = HarnessTokenEvent(
        sessionID: "s1", cwd: "/tmp/proj", provider: "p", model: "m",
        tsMs: harnessTs(2026, 10, 19),
        usage: HarnessTokenUsage(uncachedInput: 10, output: 20, cacheRead: 30,
                                 cacheWrite: 40, requestCount: 1))
    assertEqual(db.harnessReplaceSession(record: record, events: [event], cwd: "/tmp/proj"), true, "事件落库成功")
    let aggregate = db.harnessAggregate(now: harnessDate(2026, 10, 19, 12))
    assertEqual(aggregate.indexedSessions, 1, "聚合立即读到 1 个会话")
    assertEqual(aggregate.allTime.requestCount, 1, "聚合立即读到 1 次请求")
    assertEqual(aggregate.allTime.totalTokens, 100, "聚合立即读到 100 token")
    assertEqual(db.harnessEventCount(), 1, "事件计数走只读连接")

    // 4) 内存库：第二个连接看不见它 → 退化走写队列，语义不变
    let memory = DatabaseManager()
    memory.initializeInMemory()
    defer { memory.close() }
    assertEqual(memory.isUsingDedicatedReadConnection, false, "内存库没有只读连接")
    _ = memory.saveClipboardItem(ClipboardDraft(kind: .text, contentHash: "hash-mem", text: "内存库"))
    assertEqual(memory.fetchClipboardItems(kind: nil, limit: 5).count, 1, "内存库只读查询仍走写队列并读到")
}
