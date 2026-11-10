import Foundation
import NetworkMonitorCore

// MARK: - 贴图内容源与恢复池（P0-11 / P0-12 回归）

/// 覆盖两条纯逻辑：
/// 1. 图片文件贴图策略 —「首贴贴图像、再贴降级为路径文本」与偏好「优先显示图像」；
/// 2. 已关闭贴图恢复池 — 上限默认 1、夹到 1...10、按上限裁剪。
func runSnipPinContentSourceTests() {
    print("🧪 Testing pin content source & recoverable pool...")

    // MARK: 已贴记录（路径 + 内容哈希）

    var signatures: Set<String> = []
    assertEqual(SnipImageFilePinTracker.isPinned(signatures, path: "/tmp/a.png", contentHash: "h1"),
                false, "新文件尚未贴过")
    signatures = SnipImageFilePinTracker.recording(signatures, path: "/tmp/a.png", contentHash: "h1")
    assertEqual(SnipImageFilePinTracker.isPinned(signatures, path: "/tmp/a.png", contentHash: "h1"),
                true, "同一路径同一哈希算已贴过")
    assertEqual(SnipImageFilePinTracker.isPinned(signatures, path: "/tmp/a.png", contentHash: "h2"),
                false, "同一路径但内容变了，算没贴过")
    assertEqual(SnipImageFilePinTracker.isPinned(signatures, path: "/tmp/b.png", contentHash: "h1"),
                false, "不同路径同一内容，算没贴过")
    assertEqual(SnipImageFilePinTracker.isPinned(signatures, path: "/tmp/a.png", contentHash: nil),
                false, "取不到哈希时按路径 + 空哈希判重，与有哈希的记录不互相命中")

    // MARK: 图片文件贴图策略

    assertEqual(SnipImageFilePinPolicy.outcome(path: "/tmp/a.png", contentHash: "h1",
                                               displayImageFiles: true, pinnedSignatures: []),
                .image(path: "/tmp/a.png"), "偏好开且没贴过 → 贴图像")
    assertEqual(SnipImageFilePinPolicy.outcome(path: "/tmp/a.png", contentHash: "h1",
                                               displayImageFiles: true, pinnedSignatures: signatures),
                .pathText, "偏好开但已贴过 → 降级为路径文本")
    assertEqual(SnipImageFilePinPolicy.outcome(path: "/tmp/a.png", contentHash: "h2",
                                               displayImageFiles: true, pinnedSignatures: signatures),
                .image(path: "/tmp/a.png"), "同一文件内容变了 → 仍贴新的图像")
    assertEqual(SnipImageFilePinPolicy.outcome(path: "/tmp/a.png", contentHash: "h1",
                                               displayImageFiles: false, pinnedSignatures: []),
                .pathText, "偏好关 → 一律直接贴路径文本")
    assertEqual(SnipImageFilePinPolicy.outcome(path: "/tmp/a.png", contentHash: nil,
                                               displayImageFiles: true, pinnedSignatures: []),
                .image(path: "/tmp/a.png"), "取不到哈希不影响首贴")

    // MARK: 路径文本拼装

    assertEqual(SnipFilePathText.joined(["/tmp/a.png"]), "/tmp/a.png", "单文件就是路径本身")
    assertEqual(SnipFilePathText.joined([" /tmp/a.png ", "/tmp/b.png"]), "/tmp/a.png\n/tmp/b.png",
                "去首尾空白后逐行拼接")
    assertEqual(SnipFilePathText.joined(["/tmp/a.png", " /tmp/a.png "]), "/tmp/a.png", "重复路径只留一条")
    assertEqual(SnipFilePathText.joined(["", "   "]) == nil, true, "全部空白时没有可贴内容")
    assertEqual(SnipFilePathText.joined([]) == nil, true, "空列表没有可贴内容")

    // MARK: 内容指纹

    let tmpDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("snip-pin-content-source-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: tmpDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDirectory) }
    let sample = tmpDirectory.appendingPathComponent("sample.png")
    let sampleBytes = Data("贴图内容指纹".utf8)
    try? sampleBytes.write(to: sample)
    assertEqual(SnipImageFileFingerprint.contentHash(ofFileAt: sample.path),
                ClipboardContentHasher.sha256Hex(sampleBytes), "内容指纹取文件字节的 SHA256")
    assertEqual(SnipImageFileFingerprint.contentHash(ofFileAt: sample.path, maxBytes: sampleBytes.count - 1) == nil,
                true, "超过字节上限时不算指纹，退化为仅按路径判重")
    assertEqual(SnipImageFileFingerprint.contentHash(ofFileAt: sample.path + ".missing") == nil,
                true, "文件不存在时算不出指纹")
    assertEqual(SnipImageFileFingerprint.contentHash(ofFileAt: "") == nil, true, "空路径算不出指纹")

    // MARK: 恢复池上限（默认 1，范围 1...10）

    assertEqual(SnipClosedPinLimit.defaultValue, 1, "官方默认建议 1")
    assertEqual(SnipClosedPinLimit.range, 1...10, "可选范围 1...10")
    assertEqual(SnipClosedPinLimit.normalized(0), 1, "偏好未设置读到 0 时回落默认 1")
    assertEqual(SnipClosedPinLimit.normalized(-5), 1, "负数夹到下界")
    assertEqual(SnipClosedPinLimit.normalized(7), 7, "范围内原值返回")
    assertEqual(SnipClosedPinLimit.normalized(99), 10, "超上界夹到 10")

    // MARK: 恢复队列裁剪

    assertEqual(SnipClosedPinRecoveryQueue.trimmed(["a", "b", "c"], limit: 1), ["a"], "上限 1 只留最近一张")
    assertEqual(SnipClosedPinRecoveryQueue.trimmed(["a", "b", "c"], limit: 3), ["a", "b", "c"], "未超上限不裁剪")
    assertEqual(SnipClosedPinRecoveryQueue.trimmed(["a", "b"], limit: 0), ["a"], "上限 0 按默认 1 处理")
    assertEqual(SnipClosedPinRecoveryQueue.enqueue("d", into: ["a", "b"], limit: 1), ["d"],
                "入队在最前，超出上限的最早一张被裁掉")
    assertEqual(SnipClosedPinRecoveryQueue.enqueue("d", into: ["a", "b"], limit: 3), ["d", "a", "b"],
                "未满时按新→旧顺序累加")
}
