import Foundation
import NetworkMonitorCore

// MARK: - 剪贴板容量清理（真实链路：内存库 + 临时目录）

/// 容量上限的「真的删了」这一半：仓储清理 + 图片文件回收 + 与按条数上限并存。
///
/// 从 ClipboardCapacityTests.swift 拆出：那个文件负责口径纯函数与输入解析（零 IO），
/// 本文件跑真实 SQLite（内存库）与真实文件 IO；两个文件都在单文件 15 KiB 门禁以内。

// MARK: - 仓储清理 + 图片文件回收（内存库 + 临时目录）

/// 入口：与 `ClipboardCapacityTests.runClipboardCapacityTests` 成对（纯逻辑 / 真实链路各一半）
func runClipboardCapacityPruneTests() {
    print("🧪 Testing Clipboard capacity prune (real path)...")
    runCapacityPruneRepositoryTests()
    runCapacityCoexistenceTests()
    runPrunerOnRealDatabaseTests()
    print("✅ Clipboard 容量清理（删最旧 / 图片文件真删 / 等于上限不删 / 0 = 不限 / 与条数并存）works")
}

private func runCapacityPruneRepositoryTests() {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("clipboard-capacity-prune", isDirectory: true)
    try? FileManager.default.removeItem(at: directory)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let db = DatabaseManager()
    db.initializeInMemory()
    defer { db.close() }

    /// 落一条图片条目：原图 + 缩略图各写一个真文件（缩略图不参与容量统计，用来验证不被误算）
    func saveImage(_ name: String, bytes: Int, createdAt: Date, pinned: Bool = false) -> ClipboardItem? {
        let original = directory.appendingPathComponent("\(name).png")
        try? Data(repeating: 5, count: bytes).write(to: original)
        try? Data(repeating: 6, count: 128).write(to: directory.appendingPathComponent("\(name)_thumb.png"))
        let item = db.saveClipboardItem(ClipboardDraft(kind: .image, contentHash: name,
                                                       imagePath: original.path, imageWidth: 8, imageHeight: 8,
                                                       createdAt: createdAt))
        if pinned, let item { _ = db.setClipboardItemPinned(id: item.id, isPinned: true) }
        return item
    }
    let byteSource = ClipboardCapacityUsage.fileByteCount(atPath:)

    let base = Date()
    let first = saveImage("cap-a", bytes: 4_096, createdAt: base)
    let second = saveImage("cap-b", bytes: 4_096, createdAt: base.addingTimeInterval(1))
    let third = saveImage("cap-c", bytes: 4_096, createdAt: base.addingTimeInterval(2))
    assertNotNil(first, "图片条目 A 落库")
    assertNotNil(second, "图片条目 B 落库")
    assertNotNil(third, "图片条目 C 落库")

    // 4.1 总量与逐条口径一致（缩略图不计）
    assertEqual(db.clipboardCapacityBytes(imageByteCount: byteSource), UInt64(3 * 4_096),
                "总占用只算三张原图（缩略图不计入）")

    // 4.2 上限高于总量：什么都不删
    assertEqual(db.pruneClipboardItemsOverCapacity(maxBytes: 100 * 1024 * 1024,
                                                   imageByteCount: byteSource).count, 0,
                "未超限时不删")

    // 4.3 上限 0 = 不限：即使远超也不删
    assertEqual(db.pruneClipboardItemsOverCapacity(maxBytes: 0, imageByteCount: byteSource).count, 0,
                "上限 0 表示不限，不删")

    // 4.4 上限 8 KB：删最旧一条后总量 8 KB（等于上限，不删）
    let pruned = db.pruneClipboardItemsOverCapacity(maxBytes: 8_192, imageByteCount: byteSource)
    assertEqual(pruned.count, 1, "超限清理删 1 条")
    assertEqual(pruned.first?.contentHash, "cap-a", "被删的是最旧一条")
    assertEqual(db.clipboardItemCount(), 2, "库里剩 2 条")
    assertEqual(db.clipboardCapacityBytes(imageByteCount: byteSource), UInt64(8_192), "总量回到 8 KB")

    // 4.5 图片文件确实被回收（判定 + 执行器都是生产 ClipboardImageGC.reclaim 复用的同一份 Core 实现）
    let logger = ConsoleLogger(minLevel: .error)
    let fileNames = ClipboardImageSweeper.fileNames(in: directory) ?? []
    let doomed = ClipboardImageSweepPlan.reclaimableFileNames(
        fileNames: fileNames,
        doomedImagePaths: Set(pruned.compactMap(\.imagePath)),
        doomedContentHashes: Set(pruned.map(\.contentHash)))
    let reclaim = ClipboardImageSweeper.remove(fileNames: doomed, in: directory, logger: logger)
    assertEqual(reclaim, 2, "被删条目的原图 + 缩略图共 2 个文件被回收到")
    assertEqual(FileManager.default.fileExists(atPath: directory.appendingPathComponent("cap-a.png").path),
                false, "被删条目的原图文件已消失")
    assertEqual(FileManager.default.fileExists(atPath: directory.appendingPathComponent("cap-a_thumb.png").path),
                false, "被删条目的缩略图文件已消失")
    assertEqual(FileManager.default.fileExists(atPath: directory.appendingPathComponent("cap-c.png").path),
                true, "保留条目的原图仍在")

    // 4.6 刚好等于上限：不再删除（8 KB 上限、8 KB 占用）
    assertEqual(db.pruneClipboardItemsOverCapacity(maxBytes: 8_192, imageByteCount: byteSource).count,
                0, "刚好等于上限不删")

    try? FileManager.default.removeItem(at: directory)
}

// MARK: - 与按条数上限并存

private func runCapacityCoexistenceTests() {
    let db = DatabaseManager()
    db.initializeInMemory()
    defer { db.close() }
    let byteSource = ClipboardCapacityUsage.fileByteCount(atPath:)
    let base = Date()

    // 10 条纯文本，每条 100 字节：总 1000 字节
    for index in 0..<10 {
        _ = db.saveClipboardItem(ClipboardDraft(kind: .text, contentHash: "co-\(index)",
                                                text: String(repeating: "x", count: 100),
                                                createdAt: base.addingTimeInterval(Double(index))))
    }
    assertEqual(db.clipboardItemCount(), 10, "先落 10 条")
    assertEqual(db.clipboardCapacityBytes(imageByteCount: byteSource), UInt64(1_000), "总量 1000 字节")

    // 5.1 两条上限同时生效：条数先收拾到 5 条，容量上限不再触发（确保顺序不互相破坏）
    let byCount = db.pruneClipboardItems(maxItems: 5, retentionDays: 30)
    assertEqual(byCount.count, 5, "按条数清理删 5 条")
    assertEqual(db.clipboardItemCount(), 5, "剩 5 条")
    let leftover = db.fetchAllClipboardItems(kind: nil)
    assertEqual(ClipboardCapacityUsage.isOverLimit(totalBytes: ClipboardCapacityUsage.totalBytes(of: leftover,
                                                                                                 imageByteCount: byteSource),
                                                    maxBytes: 1_000), false,
                "条数清理后容量已在上限内，容量清理不会再动手")

    // 5.2 反过来：条数上限宽松、容量上限紧 → 只由容量删，且不破坏条数上限
    for index in 10..<20 {
        _ = db.saveClipboardItem(ClipboardDraft(kind: .text, contentHash: "co-\(index)",
                                                text: String(repeating: "y", count: 100),
                                                createdAt: base.addingTimeInterval(Double(index))))
    }
    assertEqual(db.clipboardItemCount(), 15, "又落 10 条，共 15 条")
    let byCapacity = db.pruneClipboardItemsOverCapacity(maxBytes: 1_200, imageByteCount: byteSource)
    assertEqual(byCapacity.count, 3, "容量上限 1200：删 3 条即可达标")
    assertEqual(db.clipboardItemCount(), 12, "条数上限（500）远未触及，剩余 12 条")
    assertEqual(db.clipboardCapacityBytes(imageByteCount: byteSource), UInt64(1_200), "总量回到 1200 字节")
    assertEqual(db.pruneClipboardItems(maxItems: 500, retentionDays: 30).isEmpty, true,
                "随后按条数清理无事可做（两条路径互不破坏）")

    // 5.3 收藏条目在容量清理中同样豁免，且计入总量
    let pinnedItem = db.saveClipboardItem(ClipboardDraft(kind: .text, contentHash: "co-pinned",
                                                         text: String(repeating: "z", count: 100),
                                                         createdAt: base.addingTimeInterval(100)))
    if let pinnedItem { _ = db.setClipboardItemPinned(id: pinnedItem.id, isPinned: true) }
    // 上限 100：只剩收藏项那 100 字节时不该删它
    let pinnedOnly = db.pruneClipboardItemsOverCapacity(maxBytes: 100, imageByteCount: byteSource)
    assertEqual(pinnedOnly.contains { $0.contentHash == "co-pinned" }, false, "收藏条目不被容量清理删除")
    assertEqual(db.fetchClipboardItem(id: pinnedItem?.id ?? UUID())?.isPinned, true, "收藏条目仍在库里")
}

// MARK: - 编排层跑在真实库上（一次调用同时应用条数与容量两条规则）

private func runPrunerOnRealDatabaseTests() {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("clipboard-capacity-pruner", isDirectory: true)
    try? FileManager.default.removeItem(at: directory)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let db = DatabaseManager()
    db.initializeInMemory()
    defer { db.close() }
    let base = Date()

    // 3 条 1 KB 图片（各带缩略图）+ 7 条 100 字节文本，共 10 条 / 3776 字节
    var items: [ClipboardItem] = []
    for index in 0..<3 {
        let original = directory.appendingPathComponent("pr-\(index).png")
        try? Data(repeating: 1, count: 1_024).write(to: original)
        try? Data(repeating: 2, count: 64).write(to: directory.appendingPathComponent("pr-\(index)_thumb.png"))
        if let item = db.saveClipboardItem(ClipboardDraft(kind: .image, contentHash: "pr-\(index)",
                                                         imagePath: original.path, imageWidth: 8, imageHeight: 8,
                                                         createdAt: base.addingTimeInterval(Double(index)))) {
            items.append(item)
        }
    }
    for index in 3..<10 {
        _ = db.saveClipboardItem(ClipboardDraft(kind: .text, contentHash: "pr-\(index)",
                                                text: String(repeating: "t", count: 100),
                                                createdAt: base.addingTimeInterval(Double(index))))
    }
    let byteSource = ClipboardCapacityUsage.fileByteCount(atPath:)
    assertEqual(db.clipboardItemCount(), 10, "落库 10 条")
    assertEqual(db.clipboardCapacityBytes(imageByteCount: byteSource), UInt64(3 * 1_024 + 7 * 100),
                "总量 = 3 张原图 + 7 条文本（缩略图不计）")

    // 条数上限 8、容量上限 1500：先按条数删 2 条最旧图片（剩 1024 + 700 = 1724 字节），
    // 容量仍超 → 再删一张最旧的图（1024），回到 700 字节
    let outcome = ClipboardLimitPruner.prune(repository: db, maxItems: 8, retentionDays: 30,
                                             maxBytes: 1_500, imageByteCount: byteSource)
    assertEqual(outcome.byCount.count, 2, "第一轮（按条数）删 2 条")
    assertEqual(outcome.byCapacity.isEmpty, false, "第二轮（按容量）接着删")
    assertEqual(outcome.removedCount, outcome.byCount.count + outcome.byCapacity.count,
                "两条规则的结果分列且不重复计数")
    assertEqual(db.clipboardCapacityBytes(imageByteCount: byteSource) <= 1_500, true,
                "清理后总量回到上限以内")
    assertEqual(db.clipboardItemCount(), 10 - outcome.removedCount, "库里的条数与删除数对得上")

    // 被删条目的图片文件（含缩略图）在临时目录里确实消失
    let logger = ConsoleLogger(minLevel: .error)
    let doomed = ClipboardImageSweepPlan.reclaimableFileNames(
        fileNames: ClipboardImageSweeper.fileNames(in: directory) ?? [],
        doomedImagePaths: Set(outcome.removed.compactMap(\.imagePath)),
        doomedContentHashes: Set(outcome.removed.map(\.contentHash)))
    _ = ClipboardImageSweeper.remove(fileNames: doomed, in: directory, logger: logger)
    assertEqual(FileManager.default.fileExists(atPath: directory.appendingPathComponent("pr-0.png").path),
                false, "最先被删条目的原图文件已消失")
    assertEqual(FileManager.default.fileExists(atPath: directory.appendingPathComponent("pr-0_thumb.png").path),
                false, "最先被删条目的缩略图文件已消失")

    try? FileManager.default.removeItem(at: directory)
}
