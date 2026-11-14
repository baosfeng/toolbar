import Foundation
import NetworkMonitorCore

// MARK: - 剪贴板图片磁盘回收（判定纯函数 + 真实文件 IO）

/// 覆盖规格 2.1「增量 A」：删除 / 清空 / 超限清理 / 孤儿清扫 都要真删文件
///
/// 判定在 ClipboardImageSweepPlan（纯函数），删除在 ClipboardImageSweeper（真 FileManager），
/// 两者就是生产路径 App 层 ClipboardImageGC 复用的同一套实现；测试用临时目录，不碰真实图片目录。
func runClipboardImageGCTests() {
    print("🧪 Testing Clipboard image GC...")
    runImageSweepPlanTests()
    runImageSweepIOTests()
    runImageReclaimAfterDeleteTests()
    runOrphanSweepTests()
    print("✅ Clipboard 图片磁盘回收（判定 / 删除 / 清空 / 超限清理 / 孤儿清扫）works")
}

// MARK: - 文件名 ↔ 内容哈希解析与判定

private func runImageSweepPlanTests() {
    assertEqual(ClipboardImageSweepPlan.hashPrefix(of: "abc123.png"), "abc123", "原图取扩展名前的主干")
    assertEqual(ClipboardImageSweepPlan.hashPrefix(of: "abc123_thumb.png"), "abc123", "缩略图去掉 _thumb.png 后缀")
    assertEqual(ClipboardImageSweepPlan.hashPrefix(of: "abc123.jpg"), "abc123", "同哈希换扩展名同样解析出主干")
    assertEqual(ClipboardImageSweepPlan.hashPrefix(of: "noext") == nil, true, "无扩展名解析失败")
    assertEqual(ClipboardImageSweepPlan.hashPrefix(of: "_thumb.png") == nil, true, "只有缩略图后缀时主干为空")
    assertEqual(ClipboardImageSweepPlan.hashPrefix(of: "") == nil, true, "空文件名解析失败")
    assertEqual(ClipboardImageSweepPlan.baseName(ofPath: "/tmp/a/b/c.png"), "c.png", "全路径取文件名")
    assertEqual(ClipboardImageSweepPlan.baseName(ofPath: ""), "", "空路径返回空串")

    let reclaimable = ClipboardImageSweepPlan.reclaimableFileNames(
        fileNames: ["h1.png", "h1_thumb.png", "h1.jpg", "h2.png", "h2_thumb.png", "junk.txt"],
        doomedImagePaths: ["/tmp/images/h1.png"],
        doomedContentHashes: ["h1"])
    assertEqual(Set(reclaimable), Set(["h1.png", "h1_thumb.png", "h1.jpg"]), "只回收被删条目对应的三个文件")
    assertEqual(ClipboardImageSweepPlan.reclaimableFileNames(fileNames: ["h1.png"],
                                                          doomedImagePaths: [],
                                                          doomedContentHashes: []).isEmpty,
                true, "无被删条目时返回空（调用方零 IO）")
    assertEqual(ClipboardImageSweepPlan.reclaimableFileNames(fileNames: ["h9.png", "h9.jpg"],
                                                          doomedImagePaths: ["/tmp/images/h9.jpg"],
                                                          doomedContentHashes: ["h9"]).count,
                2, "DB 路径扩展名与磁盘不一致时同哈希副本一并回收")

    let orphans = ClipboardImageSweepPlan.orphanFileNames(
        fileNames: ["live.png", "live_thumb.png", "livehash-img.jpg", "dead.png", "dead_thumb.png", "junk.txt"],
        keptImagePaths: ["/tmp/images/live.png"],
        keptContentHashes: ["livehash-img"])
    // live.png 靠「路径命中」保留；livehash-img.jpg 靠「哈希命中」保留；
    // live_thumb.png 两条都不命中 → 孤儿（真实场景里 DB 的 content_hash 集合会含 "live"，此处刻意造出更严的输入）
    assertEqual(Set(orphans), Set(["live_thumb.png", "dead.png", "dead_thumb.png", "junk.txt"]),
                "无引用文件判为孤儿（路径命中与哈希命中各保留一个）")
    assertEqual(ClipboardImageSweepPlan.orphanFileNames(fileNames: [], keptImagePaths: [],
                                                       keptContentHashes: []).isEmpty, true, "空目录无孤儿")

    print("✅ Clipboard 图片回收判定（文件名解析 / 被删关联 / 孤儿）works")
}

// MARK: - 真实文件 IO 夹具

private func makeClipGCTempDirectory(_ name: String) -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("clipboard-image-gc-\(name)", isDirectory: true)
    try? FileManager.default.removeItem(at: url)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@discardableResult
private func writeClipGCFile(_ name: String, in directory: URL, bytes: Int = 16) -> URL {
    let url = directory.appendingPathComponent(name)
    try? Data(repeating: 7, count: bytes).write(to: url)
    return url
}

private func clipGCFileExists(_ name: String, in directory: URL) -> Bool {
    FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path)
}

// MARK: - 删除执行器（真实文件 IO）

private func runImageSweepIOTests() {
    let directory = makeClipGCTempDirectory("io")
    let logger = ConsoleLogger(minLevel: .error)
    let files = ["aa.png", "aa_thumb.png", "bb.png", "bb_thumb.png", "junk.txt"]
    for name in files { writeClipGCFile(name, in: directory) }

    assertEqual(ClipboardImageSweeper.fileNames(in: directory)?.count, files.count, "目录内文件名全量列举")
    let doomed = ClipboardImageSweepPlan.reclaimableFileNames(
        fileNames: ClipboardImageSweeper.fileNames(in: directory) ?? [],
        doomedImagePaths: [directory.appendingPathComponent("aa.png").path],
        doomedContentHashes: ["aa"])
    assertEqual(ClipboardImageSweeper.remove(fileNames: doomed, in: directory, logger: logger), 2,
                "回收删除 2 个文件")
    assertEqual(clipGCFileExists("aa.png", in: directory), false, "被删条目的原图已消失")
    assertEqual(clipGCFileExists("aa_thumb.png", in: directory), false, "被删条目的缩略图已消失")
    assertEqual(clipGCFileExists("bb.png", in: directory), true, "未涉及条目的原图保留")
    assertEqual(clipGCFileExists("bb_thumb.png", in: directory), true, "未涉及条目的缩略图保留")
    assertEqual(ClipboardImageSweeper.remove(fileNames: ["missing.png"], in: directory, logger: logger), 0,
                "删除不存在的文件返回 0 且不抛错")
    assertEqual(ClipboardImageSweeper.remove(fileNames: [], in: directory, logger: logger), 0, "空列表删除 0 个")
    let missing = directory.appendingPathComponent("not-there", isDirectory: true)
    assertEqual(ClipboardImageSweeper.fileNames(in: missing) == nil, true, "目录不存在时列举返回 nil")
    assertEqual(ClipboardImageSweeper.remove(fileNames: ["x.png"], in: missing, logger: logger), 0,
                "目录不存在时删除 0 个且不报错")
    try? FileManager.default.removeItem(at: directory)
    print("✅ Clipboard 图片删除执行器（真实文件 IO）works")
}
// MARK: - 删除 / 清空 / 超限清理 → 图片回收（真实 DB + 真实文件）

/// 覆盖 A 组行为断言：删除单条、清空（保留收藏）、超限清理之后对应文件真的不存在
private func runImageReclaimAfterDeleteTests() {
    let directory = makeClipGCTempDirectory("repo")
    let logger = ConsoleLogger(minLevel: .error)
    let db = DatabaseManager()
    db.initializeInMemory()
    defer { db.close() }

    func saveImage(_ hash: String, pinned: Bool = false, createdAt: Date = Date()) -> ClipboardItem? {
        let original = writeClipGCFile("hash-\(hash).png", in: directory)
        writeClipGCFile("hash-\(hash)_thumb.png", in: directory)
        let item = db.saveClipboardItem(ClipboardDraft(kind: .image, contentHash: "hash-\(hash)",
                                                    imagePath: original.path,
                                                    imageWidth: 8, imageHeight: 8,
                                                    createdAt: createdAt))
        if pinned, let item { _ = db.setClipboardItemPinned(id: item.id, isPinned: true) }
        return item
    }
    // 断言用的回收实现 == 生产 ClipboardImageGC 的两步（判定 + 删除执行器）
    func reclaim(_ items: [ClipboardItem]) -> Int {
        let fileNames = ClipboardImageSweeper.fileNames(in: directory) ?? []
        let doomed = ClipboardImageSweepPlan.reclaimableFileNames(
            fileNames: fileNames,
            doomedImagePaths: Set(items.compactMap(\.imagePath)),
            doomedContentHashes: Set(items.map(\.contentHash)))
        return ClipboardImageSweeper.remove(fileNames: doomed, in: directory, logger: logger)
    }
    func exists(_ name: String) -> Bool { clipGCFileExists(name, in: directory) }

    // 1) 删除单条 → 返回被删条目，原图与缩略图都不存在
    let doomedItem = saveImage("a")
    assertNotNil(doomedItem, "图片条目 A 落库成功")
    _ = saveImage("keep")
    let deleted = db.deleteClipboardItem(id: doomedItem?.id ?? UUID())
    assertEqual(deleted?.contentHash, "hash-a", "删除单条返回被删条目")
    assertEqual(reclaim(deleted.map { [$0] } ?? []), 2, "删除单条回收原图 + 缩略图")
    assertEqual(exists("hash-a.png"), false, "删除单条后原图消失")
    assertEqual(exists("hash-a_thumb.png"), false, "删除单条后缩略图消失")
    assertEqual(exists("hash-keep.png"), true, "其他条目图片不受影响")
    assertEqual(db.deleteClipboardItem(id: UUID()) == nil, true, "删除不存在的 id 返回 nil")

    // 2) 清空（保留收藏）→ 收藏图片保留，其余删除
    let pinned = saveImage("pinned", pinned: true)
    // save 返回的是落库时的值快照，收藏后需回读才能看到 isPinned
    assertEqual(db.fetchClipboardItem(id: pinned?.id ?? UUID())?.isPinned, true, "收藏条目已置顶")
    _ = saveImage("plain")
    // 库里此时有 2 条非收藏（上一步保留的 keep + 新增的 plain）与 1 条收藏
    let cleared = db.clearClipboardItems(keepingPinned: true)
    assertEqual(cleared.count, 2, "清空删除 2 条非收藏（keep + plain）")
    assertEqual(cleared.contains { $0.isPinned }, false, "被删条目不含收藏项")
    assertEqual(reclaim(cleared), 4, "清空回收 4 个文件（2 条 × 原图 + 缩略图）")
    assertEqual(exists("hash-plain.png"), false, "清空后被删图片消失")
    assertEqual(exists("hash-plain_thumb.png"), false, "清空后被删缩略图消失")
    assertEqual(exists("hash-pinned.png"), true, "收藏图片保留")
    assertEqual(exists("hash-pinned_thumb.png"), true, "收藏缩略图保留")

    // 3) 全清 → 收藏条目也被删，其图片一并回收
    let allCleared = db.clearClipboardItems(keepingPinned: false)
    assertEqual(allCleared.count, 1, "全清删除 1 条收藏")
    assertEqual(reclaim(allCleared), 2, "全清回收收藏图片 2 个文件")
    assertEqual(exists("hash-pinned.png"), false, "全清后收藏原图消失")

    // 4) 超限清理 → 被清理条目的图片删除
    let base = Date()
    for index in 0..<5 {
        _ = saveImage("prune-\(index)", createdAt: base.addingTimeInterval(Double(index)))
    }
    let pruned = db.pruneClipboardItems(maxItems: 2, retentionDays: 30)
    assertEqual(pruned.count, 3, "超限清理返回 3 条被删条目")
    assertEqual(reclaim(pruned), 6, "超限清理回收 6 个文件（3 条 × 原图 + 缩略图）")
    assertEqual(exists("hash-prune-0.png"), false, "被清理条目原图消失")
    assertEqual(exists("hash-prune-0_thumb.png"), false, "被清理条目缩略图消失")
    assertEqual(exists("hash-prune-4.png"), true, "保留条目的图片仍在")
    try? FileManager.default.removeItem(at: directory)
    print("✅ Clipboard 删除 / 清空 / 超限清理 → 图片文件真实回收 works")
}

// MARK: - 孤儿清扫（启动后一次）

private func runOrphanSweepTests() {
    let directory = makeClipGCTempDirectory("orphan")
    let logger = ConsoleLogger(minLevel: .error)
    let db = DatabaseManager()
    db.initializeInMemory()
    defer { db.close() }

    let live = writeClipGCFile("live.png", in: directory)
    writeClipGCFile("live_thumb.png", in: directory)
    _ = db.saveClipboardItem(ClipboardDraft(kind: .image, contentHash: "live",
                                            imagePath: live.path, imageWidth: 8, imageHeight: 8))
    writeClipGCFile("dead.png", in: directory)
    writeClipGCFile("dead_thumb.png", in: directory)
    writeClipGCFile("junk.txt", in: directory)

    let items = db.fetchAllClipboardItems(kind: nil)
    let orphans = ClipboardImageSweepPlan.orphanFileNames(
        fileNames: ClipboardImageSweeper.fileNames(in: directory) ?? [],
        keptImagePaths: Set(items.compactMap(\.imagePath)),
        keptContentHashes: Set(items.map(\.contentHash)))
    assertEqual(Set(orphans), Set(["dead.png", "dead_thumb.png", "junk.txt"]),
                "孤儿 = 无记录文件 + 非约定命名文件")
    assertEqual(ClipboardImageSweeper.remove(fileNames: orphans, in: directory, logger: logger), 3,
                "孤儿清扫删除 3 个文件")
    assertEqual(clipGCFileExists("live.png", in: directory), true, "有记录的图片保留")
    assertEqual(clipGCFileExists("live_thumb.png", in: directory), true, "有记录的缩略图保留")
    assertEqual(clipGCFileExists("dead.png", in: directory), false, "孤儿图片被删除")
    assertEqual(clipGCFileExists("junk.txt", in: directory), false, "非约定命名文件被删除")

    // 空目录 + 已知集合为空：不报错
    let empty = makeClipGCTempDirectory("orphan-empty")
    assertEqual(ClipboardImageSweepPlan.orphanFileNames(
        fileNames: ClipboardImageSweeper.fileNames(in: empty) ?? [],
        keptImagePaths: [], keptContentHashes: []).isEmpty, true, "空目录 + 空已知集合时无待删文件")
    assertEqual(ClipboardImageSweeper.remove(fileNames: [], in: empty, logger: logger), 0, "空目录清扫不报错")
    try? FileManager.default.removeItem(at: directory)
    try? FileManager.default.removeItem(at: empty)
    print("✅ Clipboard 图片孤儿清扫（有记录保留 / 无记录删除）works")
}
