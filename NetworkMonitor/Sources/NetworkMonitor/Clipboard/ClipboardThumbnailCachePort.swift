import AppKit
import NetworkMonitorCore
import NetworkMonitorFeatureClipboard

// MARK: - 缩略图缓存端口适配

/// 缩略图缓存端口由卡片视图那份 NSCache 适配 —— 服务层只认「按内容哈希存取」
///
/// 缓存实例留在 App（与卡片重绘同一份实例，面板收起时不清、成本上限来自 Core 的
/// ClipboardImagePolicy），故在这里做一层薄适配，而不是把 NSImage 缓存搬进服务层。
@MainActor
final class ClipboardCardThumbnailCache: ClipboardThumbnailCaching {

    func thumbnail(forKey key: String) -> NSImage? {
        ClipboardCardView.thumbnailCache.object(forKey: key as NSString)
    }

    func store(_ image: NSImage, forKey key: String, cost: Int) {
        ClipboardCardView.thumbnailCache.setObject(image, forKey: key as NSString, cost: cost)
    }
}

// MARK: - 共享解码器

/// 解码器仍是共享实例（卡片资源是无状态的纯查询路径，不进组合根）
///
/// 服务层不持有单例（它拿不到 App 的 logger 与缓存），由 App 侧补一个装配好的实例：
/// 调用点写 ClipboardThumbnailLoader.shared，与迁移前一致。
extension ClipboardThumbnailLoader {
    static let shared = ClipboardThumbnailLoader(logger: AppContext.shared.logger,
                                                 cache: ClipboardCardThumbnailCache())
}
