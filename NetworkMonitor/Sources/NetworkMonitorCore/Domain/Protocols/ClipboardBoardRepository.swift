import Foundation

// MARK: - 剪贴板板仓储

/// 板的分组仓储协议 — 与 `ClipboardRepository` 平级的新领域，不往既有协议塞方法
///
/// 线程模型与容错约定同 `ClipboardRepository`：数据库未就绪时一律返回空值（nil / [] / false），
/// 只记 logger.debug，不崩溃、不抛错。
public protocol ClipboardBoardRepository: AnyObject, Sendable {

    /// 全部板，按 sortOrder 升序、同序按创建时间升序
    func fetchBoards() -> [ClipboardBoard]

    /// 新建板：色板下标按现有板数轮转，顺序排在末位
    /// - Parameter name: 板名；空白输入归一化为「未命名板」
    /// - Returns: 落库后的板；数据库不可用时 nil
    @discardableResult
    func createBoard(name: String) -> ClipboardBoard?

    /// 改名（只改名字，不动顺序与颜色）
    /// - Returns: 是否命中并更新；空白名按归一化口径写入
    @discardableResult
    func renameBoard(id: UUID, name: String) -> Bool

    /// 删除板：**连带删除板内全部条目**
    ///
    /// 返回被删条目而不是 Bool —— 上层据此回收这些条目的落盘原图与缩略图。
    /// - Returns: 板内当时存在的条目（空数组 = 板为空或板不存在）
    @discardableResult
    func deleteBoard(id: UUID) -> [ClipboardItem]

    /// 移动条目归属：`boardID` 为 nil 表示移回「未归类」
    /// - Returns: 是否命中并更新
    @discardableResult
    func moveItemToBoard(itemID: UUID, boardID: UUID?) -> Bool

    /// 某块板内的条目（排序同 `fetchAllClipboardItems`：收藏优先 + 创建时间倒序）
    func fetchClipboardItems(boardID: UUID) -> [ClipboardItem]
}
