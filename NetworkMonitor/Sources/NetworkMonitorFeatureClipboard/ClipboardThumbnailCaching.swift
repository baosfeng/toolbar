import AppKit

// MARK: - 缩略图缓存端口

/// 缩略图解码结果的内存缓存 —— 服务层只认「按内容哈希存取」，不认缓存实例从哪来
///
/// 为什么立端口：缓存的持有者是 App 层的卡片视图（ClipboardCardView.thumbnailCache，
/// 与卡片重绘同一份实例，面板收起时不清），服务层不该反向依赖 App 的可执行目标。
/// 真实实现是 App 侧一个薄适配器（ClipboardCardThumbnailCache）。
///
/// 线程模型：只在主线程调用（ClipboardThumbnailLoader 是 @MainActor）。
@MainActor
public protocol ClipboardThumbnailCaching: AnyObject {

    /// 读缓存（未命中返回 nil）
    func thumbnail(forKey key: String) -> NSImage?

    /// 写缓存（cost 与 Core 的 ClipboardImagePolicy.decodedBytes 同一口径）
    func store(_ image: NSImage, forKey key: String, cost: Int)
}
