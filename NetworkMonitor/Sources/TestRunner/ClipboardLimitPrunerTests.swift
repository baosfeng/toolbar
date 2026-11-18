import Foundation
import NetworkMonitorCore

// MARK: - 超限清理编排（先条数后容量的顺序断言 + 偏好注入）

/// 覆盖两件「只靠读代码无法确认」的事：
/// 1. 一轮清理里**先按条数、再按容量**（顺序是行为，用记录调用序列的替身断言）；
/// 2. 仓储缺容量能力时不炸、按条数那半照常生效；
/// 3. `clipboard.maxBytes` 偏好的默认值 / 0 = 不限 / 非法值回落，且走注入存储不碰真实偏好。
func runClipboardLimitPrunerTests() {
    print("🧪 Testing Clipboard limit pruner...")
    runPrunerOrderTests()
    runPrunerWithoutCapacityTests()
    runMaxBytesPreferenceTests()
    print("✅ Clipboard 超限清理编排（先条数后容量 / 缺能力降级 / maxBytes 偏好）works")
}

// MARK: - 记录调用序列的替身

private final class RecordingCapacityRepository: @unchecked Sendable, ClipboardRepository,
                                                 ClipboardCapacityPruneRepository {

    /// 调用序列（"count" / "capacity"），用于断言顺序
    private(set) var calls: [String] = []
    private let lock = NSLock()

    func pruneClipboardItems(maxItems: Int, retentionDays: Int) -> [ClipboardItem] {
        lock.lock(); defer { lock.unlock() }
        calls.append("count")
        return [ClipboardItem(kind: .text, text: "by-count", contentHash: "c")]
    }

    func pruneClipboardItemsOverCapacity(maxBytes: UInt64,
                                         imageByteCount: (String) -> UInt64) -> [ClipboardItem] {
        lock.lock(); defer { lock.unlock() }
        calls.append("capacity")
        return [ClipboardItem(kind: .text, text: "by-capacity", contentHash: "b")]
    }

    func clipboardCapacityBytes(imageByteCount: (String) -> UInt64) -> UInt64 { 0 }

    // 其余接口在本测试里不被调用，给出最小实现
    func saveClipboardItem(_ draft: ClipboardDraft) -> ClipboardItem? { nil }
    func fetchClipboardItem(id: UUID) -> ClipboardItem? { nil }
    func fetchClipboardItems(kind: ClipboardItemKind?, limit: Int) -> [ClipboardItem] { [] }
    func fetchAllClipboardItems(kind: ClipboardItemKind?) -> [ClipboardItem] { [] }
    func searchClipboardItems(query: String, limit: Int) -> [ClipboardItem] { [] }
    func setClipboardItemPinned(id: UUID, isPinned: Bool) -> Bool { false }
    func deleteClipboardItem(id: UUID) -> ClipboardItem? { nil }
    func clearClipboardItems(keepingPinned: Bool) -> [ClipboardItem] { [] }
    func updateClipboardItemText(id: UUID, text: String, preview: String) -> ClipboardItem? { nil }
    func createClipboardItem(text: String) -> ClipboardItem? { nil }
    func updateClipboardStackPositions(_ orderedIDs: [UUID]) {}
    func fetchClipboardStack() -> [ClipboardItem] { [] }
    func clipboardItemCount() -> Int { 0 }
}

// MARK: - 顺序

private func runPrunerOrderTests() {
    let repository = RecordingCapacityRepository()
    let outcome = ClipboardLimitPruner.prune(repository: repository, maxItems: 100, retentionDays: 30,
                                             maxBytes: 1_000,
                                             imageByteCount: ClipboardCapacityUsage.fileByteCount(atPath:))
    assertEqual(repository.calls, ["count", "capacity"], "同一轮清理里先按条数、再按容量")
    assertEqual(outcome.byCount.count, 1, "按条数那半的结果单独可读")
    assertEqual(outcome.byCapacity.count, 1, "按容量那半的结果单独可读")
    assertEqual(outcome.removedCount, 2, "合计删除条数")
    assertEqual(outcome.removed.map(\.contentHash), ["c", "b"], "合并顺序：条数在前、容量在后")
    assertEqual(outcome.isEmpty, false, "有删除时 isEmpty=false")

    // 上限 = 0（不限）：仍然先跑按条数，但不再问容量
    let unlimitedRepository = RecordingCapacityRepository()
    _ = ClipboardLimitPruner.prune(repository: unlimitedRepository, maxItems: 100, retentionDays: 30,
                                   maxBytes: 0,
                                   imageByteCount: ClipboardCapacityUsage.fileByteCount(atPath:))
    assertEqual(unlimitedRepository.calls, ["count"], "上限 0 时跳过容量清理，只跑按条数")

    print("✅ Clipboard 清理顺序（先条数后容量 / 0 = 不限时跳过容量）works")
}

// MARK: - 缺容量能力时降级

private func runPrunerWithoutCapacityTests() {
    // 只实现 ClipboardRepository（模拟旧 mock / 测试替身）：容量那半静默跳过，不崩
    final class CountOnlyRepository: @unchecked Sendable, ClipboardRepository {
        func pruneClipboardItems(maxItems: Int, retentionDays: Int) -> [ClipboardItem] {
            [ClipboardItem(kind: .text, text: "only", contentHash: "only")]
        }
        func saveClipboardItem(_ draft: ClipboardDraft) -> ClipboardItem? { nil }
        func fetchClipboardItem(id: UUID) -> ClipboardItem? { nil }
        func fetchClipboardItems(kind: ClipboardItemKind?, limit: Int) -> [ClipboardItem] { [] }
        func fetchAllClipboardItems(kind: ClipboardItemKind?) -> [ClipboardItem] { [] }
        func searchClipboardItems(query: String, limit: Int) -> [ClipboardItem] { [] }
        func setClipboardItemPinned(id: UUID, isPinned: Bool) -> Bool { false }
        func deleteClipboardItem(id: UUID) -> ClipboardItem? { nil }
        func clearClipboardItems(keepingPinned: Bool) -> [ClipboardItem] { [] }
        func updateClipboardItemText(id: UUID, text: String, preview: String) -> ClipboardItem? { nil }
        func createClipboardItem(text: String) -> ClipboardItem? { nil }
        func updateClipboardStackPositions(_ orderedIDs: [UUID]) {}
        func fetchClipboardStack() -> [ClipboardItem] { [] }
        func clipboardItemCount() -> Int { 0 }
    }
    let outcome = ClipboardLimitPruner.prune(repository: CountOnlyRepository(),
                                            maxItems: 1, retentionDays: 30, maxBytes: 1_000,
                                            imageByteCount: ClipboardCapacityUsage.fileByteCount(atPath:))
    assertEqual(outcome.byCount.count, 1, "缺容量能力时按条数那半照常生效")
    assertEqual(outcome.byCapacity.isEmpty, true, "缺容量能力时容量那半返回空，不抛错")
    assertEqual(ClipboardLimitPruner.pruneOverCapacity(repository: CountOnlyRepository(),
                                                       maxBytes: 1_000,
                                                       imageByteCount: ClipboardCapacityUsage.fileByteCount(atPath:)).isEmpty,
                true, "单独跑容量清理同样安全降级")

    print("✅ Clipboard 清理降级（缺容量能力时按条数照常生效）works")
}

// MARK: - maxBytes 偏好

private func runMaxBytesPreferenceTests() {
    // 偏好层只做存储读写，归一化口径在 ClipboardLimit.normalizedMaxBytes（纯函数，这里是判据本尊）
    assertEqual(ClipboardLimit.defaultMaxBytes, UInt64(100 * 1024 * 1024), "默认值就是 100 MB")

    assertEqual(ClipboardLimit.normalizedMaxBytes(stored: nil), ClipboardLimit.defaultMaxBytes,
                "缺键回落默认值")
    assertEqual(ClipboardLimit.normalizedMaxBytes(stored: -1), ClipboardLimit.defaultMaxBytes,
                "负值回落默认值（不产生无符号下溢）")
    assertEqual(ClipboardLimit.normalizedMaxBytes(stored: 0), 0,
                "0 = 不限是合法值，必须原样透出（不能被归一化成默认值）")
    assertEqual(ClipboardLimit.normalizedMaxBytes(stored: 5 * 1024 * 1024), UInt64(5 * 1024 * 1024),
                "合法字节数原样透出")

    print("✅ Clipboard maxBytes 归一化（默认 100 MB / 0 = 不限 / 缺键与负值回落）works")
}
