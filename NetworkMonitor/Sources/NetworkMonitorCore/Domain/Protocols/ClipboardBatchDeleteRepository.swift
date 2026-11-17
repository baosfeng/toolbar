import Foundation

// MARK: - 剪贴板批量删除仓储

/// 批量删除能力 —— 接口隔离：多选删除是新领域，不往 `ClipboardRepository` 塞方法
///
/// 为什么独立成协议而不是加进 `ClipboardRepository`：那个协议已经被测试 mock 与
/// 快照路径实现，加一个必选方法会迫使所有实现都跟着写一遍与自身无关的批量删除；
/// 控制器按能力转成 `any ClipboardBatchDeleteRepository` 使用，实现方缺这条能力时
/// 退化为逐条删除（语义一致，只是多几次事务）。
public protocol ClipboardBatchDeleteRepository: AnyObject, Sendable {

    /// 批量删除指定条目（返回被删条目，供上层回收其落盘图片）
    ///
    /// 语义与单条删除一致：先取被删行、再删行、单事务；集合为空时不做任何写入，
    /// 不在库里的 id 静默忽略。
    /// - Parameter ids: 待删条目 id 集合
    /// - Returns: 实际删除的条目列表（空数组 = 没有删除）
    @discardableResult
    func deleteClipboardItems(ids: Set<UUID>) -> [ClipboardItem]
}
