import Foundation

// MARK: - 存储上限与默认值

/// 剪贴板历史的上限与默认值（单一来源，Core 与 App 共用）
public enum ClipboardLimit {
    /// 单条文本上限（UTF-8 字节）：超出后按字节边界截断落库，不丢弃整条
    public static let maxTextBytes = 1_048_576
    /// 单条图片上限（字节）：超出后跳过落库（避免大图撑爆磁盘与内存）
    public static let maxImageBytes = 20 * 1024 * 1024
    /// 摘要最大字符数（卡片视图 4 行摘要）
    public static let previewMaxLength = 200
    /// 默认最大保留条数（仅统计非收藏项）
    public static let defaultMaxItems = 500
    /// 默认保留天数（仅清理非收藏项）
    public static let defaultRetentionDays = 30
}

// MARK: - 剪贴板仓储

/// 剪贴板历史仓储协议 — 新增领域，独立于 DatabaseService
///
/// 线程模型：实现须自行保证线程安全（DatabaseManager 实现全部经由其串行队列同步执行）。
/// 容错约定（实现必须遵守，不得崩溃）：
/// - 数据库未初始化（连接为空）时，所有方法返回空值（nil / [] / 0 / false），仅记 logger.debug
/// - 非法入参归一化：limit ≤ 0 → 返回空数组；非正的 maxItems / retentionDays → 取默认值
public protocol ClipboardRepository: AnyObject, Sendable {

    /// 保存一条采集内容（单条原子 upsert 去重，禁止「先查后插」）
    ///
    /// 语义：命中 content_hash 冲突时保留库中原 id、copy_count + 1、created_at 刷新为入参时间；
    /// 未命中时以新 UUID 插入且 copy_count = 1。
    /// - Parameter draft: 采集草稿；content_hash 为空串视为无效，直接跳过
    /// - Returns: 落库后的最新行；无效入参或数据库不可用时返回 nil
    @discardableResult
    func saveClipboardItem(_ draft: ClipboardDraft) -> ClipboardItem?

    /// 按 id 查询单条（不存在或数据库不可用返回 nil）
    func fetchClipboardItem(id: UUID) -> ClipboardItem?

    /// 分页查询：置顶（收藏）优先，其次按创建时间倒序
    /// - Parameters:
    ///   - kind: nil 表示全部类型
    ///   - limit: 期望条数；≤ 0 归一化为空结果
    func fetchClipboardItems(kind: ClipboardItemKind?, limit: Int) -> [ClipboardItem]

    /// 全量查询（供面板内存过滤与模糊搜索；排序同上）
    /// - Parameter kind: nil 表示全部类型
    func fetchAllClipboardItems(kind: ClipboardItemKind?) -> [ClipboardItem]

    /// 全文检索：对 text 与 preview 与来源 App 名做大小写不敏感子串匹配
    /// - Parameters:
    ///   - query: 查询串；空串或全空白 → 返回空数组（由调用方决定是否回退全量）
    ///   - limit: 最大返回条数；≤ 0 → 返回空数组
    /// - Returns: 命中条目，排序与 fetchClipboardItems 一致（收藏优先 + created_at 倒序）
    func searchClipboardItems(query: String, limit: Int) -> [ClipboardItem]

    /// 收藏 / 取消收藏（收藏即置顶，落 is_pinned 与 pinned_at 两列）
    /// - Returns: 是否命中并更新
    @discardableResult
    func setClipboardItemPinned(id: UUID, isPinned: Bool) -> Bool

    /// 删除单条
    /// - Returns: 是否命中并删除
    @discardableResult
    func deleteClipboardItem(id: UUID) -> Bool

    /// 清空历史
    /// - Parameter keepingPinned: true = 保留收藏项（默认交互，对应 ⌘⇧⌫）
    /// - Returns: 实际删除条数
    @discardableResult
    func clearClipboardItems(keepingPinned: Bool) -> Int

    /// 重写 Paste Stack 顺序：数组下标 + 1 写入 stack_position，未列出的条目清空为 NULL
    /// - Parameter orderedIDs: 从队首到队尾的条目 id；空数组 = 清空整栈
    func updateClipboardStackPositions(_ orderedIDs: [UUID])

    /// 读取栈内条目（按 stack_position 升序）
    func fetchClipboardStack() -> [ClipboardItem]

    /// 超限清理：条数超过 maxItems 或早于 retentionDays 的非收藏项会被删除
    /// - Parameters:
    ///   - maxItems: ≤ 0 时取 ClipboardLimit.defaultMaxItems
    ///   - retentionDays: ≤ 0 时取 ClipboardLimit.defaultRetentionDays
    /// - Returns: 实际删除条数
    @discardableResult
    func pruneClipboardItems(maxItems: Int, retentionDays: Int) -> Int

    /// 当前条目总数（含收藏）
    func clipboardItemCount() -> Int
}
