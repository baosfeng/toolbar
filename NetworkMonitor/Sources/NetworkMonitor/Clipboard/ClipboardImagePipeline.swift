import Foundation
import NetworkMonitorCore

// MARK: - 图片采集后台流水线

/// 图片采集的后台流水线 —— 哈希 / 原图落盘 / ImageIO 缩略图 / PNG 编码全部在这里发生
///
/// 采集端（`PasteboardWatcher`）只做两件事：在主线程读 pasteboard 字节（`NSPasteboard` 的线程约束）、
/// 把字节交给本 actor。5K 图的哈希 + 落盘 + 缩略图 + 缩略图 PNG 编码实测 100ms 级
/// （见 /tmp/hang-report.md §1.3 与 `NM_CLIPBOARD_CAPTURE_TIMING` 取证），留在主线程会让面板掉帧。
///
/// actor 串行：一次采集只产出一条结果；连续两次复制也按到达顺序结算，
/// 不会出现「后复制的先落库」把列表顺序打乱。
actor ClipboardImagePipeline {

    /// 共享实例（无状态、串行结算，不需要进组合根）
    static let shared = ClipboardImagePipeline()

    /// 处理结果
    struct Result: Sendable {
        /// 内容哈希（去重口径，与旧同步路径同一函数产出）
        let contentHash: String
        /// 落盘结局；nil = 字节不可解码 / IO 失败（与旧同步路径的 `continue` / `nil` 等价）
        let outcome: ClipboardImageStore.Outcome?
    }

    /// 处理一份图片字节：内容哈希 → 像素守卫 + 原图落盘 + 缩略图
    ///
    /// - Parameters:
    ///   - data: 主线程从 pasteboard 读到的原始字节（PNG / TIFF 等待选之一）
    ///   - logger: 日志（`LoggingService` 是 Sendable，可直接跨 actor 使用）
    /// - Parameters:
    ///   - data: 主线程从 pasteboard 读到的原始字节（PNG / TIFF 等待选之一）
    ///   - isOversized: 原始字节已超单图上限（超限条目不落盘，只按头部尺寸产出占位）
    func process(data: Data, isOversized: Bool, logger: LoggingService) -> Result? {
        // 超限条目也要能进历史（占位），所以哈希不按单图上限截断
        guard let contentHash = ClipboardContentHasher.prepareImageData(
            data, maxBytes: isOversized ? Int.max : ClipboardLimit.maxImageBytes) else { return nil }
        let outcome = isOversized
            ? ClipboardImageStore.oversizedOutcome(data: data)
            : ClipboardImageStore.store(data: data, contentHash: contentHash, logger: logger)
        return Result(contentHash: contentHash, outcome: outcome)
    }
}
