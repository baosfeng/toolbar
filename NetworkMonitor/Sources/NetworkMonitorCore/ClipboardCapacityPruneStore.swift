import Foundation

// MARK: - 剪贴板容量超限清理（SQLite 实现）

/// 容量超限清理的实现 —— 独立成文件：同族门禁按类名前缀聚合行数，
/// 塞进 `DatabaseManager+ClipboardRepository.swift` 只会撑大既有族。
///
/// 分工：
/// - 条目的字节与「该删哪些」全在 `ClipboardCapacityUsage`（纯函数，可单测）；
/// - 本文件只负责取全量条目、拿被删行、提交删除；
/// - 删除与「按条数」清理共用 `clipDeleteBatch`（先取被删行、再删行、单事务），
///   所以上层回收落盘图片（`ClipboardImageGC.reclaim`）对两条路径是同一份代码。
extension DatabaseManager: ClipboardCapacityPruneRepository {

    public func pruneClipboardItemsOverCapacity(maxBytes: UInt64,
                                                imageByteCount: (String) -> UInt64) -> [ClipboardItem] {
        guard maxBytes != ClipboardCapacityUsage.unlimited else { return [] }
        // 全量条目（含收藏 / 板内条目：它们计入总量，只是不参与删除）
        let items = fetchAllClipboardItems(kind: nil)
        guard !items.isEmpty else { return [] }
        let counts = ClipboardCapacityUsage.byteCounts(of: items, imageByteCount: imageByteCount)
        let doomed = ClipboardCapacityUsage.overflowIDs(of: items, byteCounts: counts, maxBytes: maxBytes)
        guard !doomed.isEmpty else { return [] }
        // 一次批量删除（所有判断都已由纯函数给出，这里不再重复算字节）
        return deleteClipboardItems(ids: Set(doomed))
    }

    public func clipboardCapacityBytes(imageByteCount: (String) -> UInt64) -> UInt64 {
        ClipboardCapacityUsage.totalBytes(of: fetchAllClipboardItems(kind: nil),
                                          imageByteCount: imageByteCount)
    }
}
