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
    /// 默认最大容量（字节）：100 MB，仅统计非收藏项的正文与图片原图；0 = 不限
    public static let defaultMaxBytes: UInt64 = 100 * 1024 * 1024

    /// 容量上限偏好的归一化：缺键（nil）与负值回落到默认值，**0 是合法值（不限）必须原样透出**
    ///
    /// 抽成纯函数是为了让「0 = 不限不能被悄悄改成默认值」这条口径可被测试直接断言，
    /// 而不是只能靠人肉点设置页确认。
    /// - Parameter stored: 偏好里存的整数（nil = 键不存在）
    public static func normalizedMaxBytes(stored: Int?) -> UInt64 {
        guard let stored, stored >= 0 else { return defaultMaxBytes }
        return UInt64(stored)
    }
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

    /// 删除单条（返回被删条目，供上层回收其落盘图片）
    /// - Returns: 被删除的条目；id 不存在或数据库不可用时为 nil
    @discardableResult
    func deleteClipboardItem(id: UUID) -> ClipboardItem?

    /// 清空历史（返回被删条目，供上层回收其落盘图片）
    /// - Parameter keepingPinned: true = 保留收藏项（默认交互，对应 ⌘⇧⌫）
    /// - Returns: 实际删除的条目列表（空数组 = 没有删除，上层据此零文件系统开销）
    @discardableResult
    func clearClipboardItems(keepingPinned: Bool) -> [ClipboardItem]

    /// 编辑一条**文本类**条目的正文（重算内容哈希，口径见下方「编辑后哈希」）
    ///
    /// 语义：
    /// - 只接受 kind 为 text / rtf 的条目；图片 / 文件条目返回 nil（走别的路径）；
    /// - 正文经 `ClipboardContentHasher.prepareText` 规范化 + 超限截断后**重算 content_hash**；
    ///   规范化后为空（空串 / 纯空白）一律不保存，返回 nil（空串没有可用的内容哈希）；
    /// - 重算后的哈希命中了**另一条**已有条目时，保留当前条目、把被冲突那条视为同一内容的
    ///   旧记录删除：copy_count 取两者之和、收藏态取或；
    /// - 编辑不改 created_at / stack_position（不置顶、不打断 Paste Stack 顺序），kind 归一为 text
    ///   （编辑输入是纯文本，RTF 样式已丢失）。
    /// - Parameter preview: 摘要；空白时由仓储按正文自动生成
    /// - Returns: 保存后的最新行；条目不存在、类型不支持、内容为空或数据库不可用时返回 nil
    @discardableResult
    func updateClipboardItemText(id: UUID, text: String, preview: String) -> ClipboardItem?

    /// 手动新建一条文本条目（面板 ⌘N，不经过系统剪贴板、不记录来源 App）
    ///
    /// 与 `saveClipboardItem` 的区别：那条是**采集落库**路径，会写来源 App 并按自激标记语义判重；
    /// 手动新建不是「从某个 App 复制来的」，故 source_bundle_id / source_app_name 一律留空，
    /// 也不涉及剪贴板自激标记（本路径从不写 NSPasteboard）。
    /// 内容哈希口径与采集一致；命中已有条目时按去重语义自增 copy_count 并刷新创建时间（置顶）。
    /// - Returns: 落库后的最新行；空白内容或数据库不可用时返回 nil
    @discardableResult
    func createClipboardItem(text: String) -> ClipboardItem?

    /// 重写 Paste Stack 顺序：数组下标 + 1 写入 stack_position，未列出的条目清空为 NULL
    /// - Parameter orderedIDs: 从队首到队尾的条目 id；空数组 = 清空整栈
    func updateClipboardStackPositions(_ orderedIDs: [UUID])

    /// 读取栈内条目（按 stack_position 升序）
    func fetchClipboardStack() -> [ClipboardItem]

    /// 超限清理：条数超过 maxItems 或早于 retentionDays 的非收藏项会被删除
    /// - Parameters:
    ///   - maxItems: ≤ 0 时取 ClipboardLimit.defaultMaxItems
    ///   - retentionDays: ≤ 0 时取 ClipboardLimit.defaultRetentionDays
    /// - Returns: 实际删除的条目列表（供上层回收其落盘图片）
    @discardableResult
    func pruneClipboardItems(maxItems: Int, retentionDays: Int) -> [ClipboardItem]

    /// 当前条目总数（含收藏）
    func clipboardItemCount() -> Int
}
