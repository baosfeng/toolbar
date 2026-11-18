import Foundation

// MARK: - 剪贴板容量超限清理

/// 按**总占用字节**超限清理的能力 —— 接口隔离：容量上限是新领域，不往 `ClipboardRepository` 塞方法
///
/// 为什么独立成协议（与 `ClipboardBatchDeleteRepository` 同一理由）：`ClipboardRepository`
/// 已被面板 mock / 快照路径 / 测试替身实现，加一条必选方法会迫使所有实现都写一遍与自身无关的能力；
/// 上层按能力写成 `repository as? any ClipboardCapacityPruneRepository`，缺这条能力时
/// 「按条数」清理照常跑，不因为容量清理缺席而整体失效。
///
/// 线程模型与容错约定同 `ClipboardRepository`：数据库未就绪返回空数组；删除与「按条数」
/// 清理共用 `clipDeleteBatch`（先取被删行、再删行、单事务），故图片回收路径完全复用。
public protocol ClipboardCapacityPruneRepository: AnyObject, Sendable {

    /// 容量超限清理：总量超过 `maxBytes` 时**从最旧开始**删除可清理条目，直到回到上限以内
    ///
    /// - Parameters:
    ///   - maxBytes: 上限字节；`0`（或负值）= 不限，不做任何删除
    ///   - imageByteCount: 图片原图路径 → 文件字节；读不到时返回 0（不计入）
    /// - Returns: 实际删除的条目列表（供上层回收落盘图片）；未超限时为空数组
    @discardableResult
    func pruneClipboardItemsOverCapacity(maxBytes: UInt64,
                                         imageByteCount: (String) -> UInt64) -> [ClipboardItem]

    /// 当前总占用字节（正文 UTF-8 字节 + 图片原图文件字节，缩略图不计；口径见 `ClipboardCapacityUsage`）
    func clipboardCapacityBytes(imageByteCount: (String) -> UInt64) -> UInt64
}
