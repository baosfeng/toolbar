import Foundation

// MARK: - 剪贴板 OCR 结果回写

/// 剪贴板 OCR 结果仓储 — 独立领域协议（不与 ClipboardRepository 混用）
///
/// 为什么单开协议：识别是后台异步写、与采集写完全不同的生命周期（采集在主线程、识别在后台），
/// 塞进 ClipboardRepository 会让面板控制器凭空依赖识别链路。实现仍由 DatabaseManager 承担。
///
/// ocr_text 三态口径（识别调度据此收敛，唯一判据见 `ClipboardOCRPolicy`）：
/// - NULL：**未识别**，唯一可调度态；
/// - 空串：已识别且无可读文字（或图片不可解、识别多次失败）——**终态**，永不再试；
/// - 正文：识别出的文字（已折叠换行并按字节上限截断）。
public protocol ClipboardOCRRepository: AnyObject, Sendable {

    /// 回写某条的识别结果（终态值，空串表示「确认无文字」）
    /// - Parameters:
    ///   - id: 条目 id
    ///   - text: 识别文本；空串写入终态标记
    /// - Returns: 是否命中并更新；数据库不可用或 id 不存在返回 false
    @discardableResult
    func updateClipboardItemOCRText(id: UUID, text: String) -> Bool
}
