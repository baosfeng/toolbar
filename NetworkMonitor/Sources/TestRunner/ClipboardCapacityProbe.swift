import Foundation
import NetworkMonitorCore

// MARK: - 剪贴板容量上限：真实链路自证探针

/// 人工触发的自证：真实 sqlite 文件库 + 真实图片目录，塞到超限后跑容量清理，
/// 打印前后「条目数 / 图片目录文件数 / 总占用」，用于验收「真的被删了」。
///
/// 触发：`swift run --disable-sandbox --build-system native TestRunner --clipboard-capacity-probe <目录>`
/// 只用 Core 的实现（`ClipboardCapacityUsage` + `ClipboardImageSweepPlan` + `ClipboardImageSweeper`），
/// 这三者正是 App 层 `ClipboardImageGC` 拼装的同一套代码，不另写一条删除路径。
func runClipboardCapacityProbe(directory path: String) {
    let root = URL(fileURLWithPath: path, isDirectory: true)
    try? FileManager.default.removeItem(at: root)
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let images = root.appendingPathComponent("images", isDirectory: true)
    try? FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)

    let db = DatabaseManager(path: root.appendingPathComponent("probe.db").path)
    db.initialize()
    let logger = ConsoleLogger(minLevel: .error)
    let byteSource = ClipboardCapacityUsage.fileByteCount(atPath:)
    func fileCount() -> Int {
        (try? FileManager.default.contentsOfDirectory(atPath: images.path))?.count ?? 0
    }
    func report(_ label: String) {
        print("\(label)：条目数=\(db.clipboardItemCount()) 图片目录文件数=\(fileCount()) "
              + "总占用=\(db.clipboardCapacityBytes(imageByteCount: byteSource)) 字节")
    }

    // 6 条图片（原图 256 KB + 缩略图 1 KB）+ 6 条 100 KB 文本 ≈ 2.1 MB
    let base = Date()
    for index in 0..<6 {
        let name = "probe-\(index)"
        let original = images.appendingPathComponent("\(name).png")
        try? Data(repeating: 0xAB, count: 256 * 1024).write(to: original)
        try? Data(repeating: 0xCD, count: 1024).write(to: images.appendingPathComponent("\(name)_thumb.png"))
        _ = db.saveClipboardItem(ClipboardDraft(kind: .image, contentHash: name, imagePath: original.path,
                                                imageWidth: 64, imageHeight: 64,
                                                createdAt: base.addingTimeInterval(Double(index))))
    }
    for index in 6..<12 {
        _ = db.saveClipboardItem(ClipboardDraft(kind: .text, contentHash: "probe-t\(index)",
                                                text: String(repeating: "x", count: 100 * 1024),
                                                createdAt: base.addingTimeInterval(Double(index))))
    }
    report("写入后")

    // 上限 1 MB：从最旧开始删到回到上限以内
    let maxBytes: UInt64 = 1024 * 1024
    let pruned = db.pruneClipboardItemsOverCapacity(maxBytes: maxBytes,
                                                    imageByteCount: byteSource)
    // 图片回收：判定 + 执行器与生产 ClipboardImageGC.reclaim 完全同一套
    let doomed = ClipboardImageSweepPlan.reclaimableFileNames(
        fileNames: ClipboardImageSweeper.fileNames(in: images) ?? [],
        doomedImagePaths: Set(pruned.compactMap(\.imagePath)),
        doomedContentHashes: Set(pruned.map(\.contentHash)))
    let removedFiles = ClipboardImageSweeper.remove(fileNames: doomed, in: images, logger: logger)

    print("上限=\(maxBytes) 字节：删除条目=\(pruned.count) 删除图片文件=\(removedFiles)")
    print("被删条目哈希：\(pruned.map(\.contentHash).sorted().joined(separator: ","))")
    report("清理后")
    print("仍存活：\(db.fetchAllClipboardItems(kind: nil).map(\.contentHash).sorted().joined(separator: ","))")
    db.close()
}
