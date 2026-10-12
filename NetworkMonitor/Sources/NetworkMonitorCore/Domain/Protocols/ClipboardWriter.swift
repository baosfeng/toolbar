import Foundation

// MARK: - 剪贴板写回

/// 写回系统剪贴板协议 — 仅协议，实现位于 App 层
///
/// 自激防护契约：本协议任何写入都必须保证「写入内容不会被自身采集器再次记录」——
/// 实现须在写入前给剪贴板打上标记类型
/// `ClipboardPasteboardType.internalMarker`，且该标记的存活期覆盖后续的合成 ⌘V
/// （同步合成窗口可显式调用 beginInternalWrite()/endInternalWrite() 延长）。
@MainActor
public protocol ClipboardWriter: AnyObject {

    /// 写回一条历史条目
    /// - Parameters:
    ///   - item: 待写回条目；图片条目从 imagePath 读取原图，文件条目写文件 URL
    ///   - asPlainText: true = 只写纯文本（对应 ⌥↵ 以纯文本粘贴）
    /// - Returns: 是否写入成功（图片文件缺失或解码失败时返回 false，调用方应提示用户）
    @discardableResult
    func write(_ item: ClipboardItem, asPlainText: Bool) -> Bool

    /// 仅写入纯文本（无历史条目时的一次性写入）
    @discardableResult
    func writeText(_ text: String) -> Bool

    /// 开始一次内部写入窗口：期间写入剪贴板的内容一律带自激标记
    /// - Note: 与 endInternalWrite() 必须配对；嵌套调用由实现自行计数或幂等处理
    func beginInternalWrite()

    /// 结束内部写入窗口并清除自激标记
    func endInternalWrite()
}
