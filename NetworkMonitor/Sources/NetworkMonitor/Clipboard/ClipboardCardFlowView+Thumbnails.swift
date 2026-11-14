import AppKit
import NetworkMonitorCore

// MARK: - 卡片流缩略图接线（从 ClipboardCardFlowView 拆出，守住单文件体积上限）

/// `ClipboardCardFlowView` 的缩略图部分 — 预取、就绪订阅、续请求与可见卡片枚举
///
/// 只走 `ClipboardThumbnailLoader` 这一条解码路径，不新增解码实现；
/// 就绪后由卡片自己 0.2s 淡入真图（`ClipboardCardView.refreshThumbnail(animated:)`）。
/// 跨文件访问：`items` / `windowStart` / `cardViews` / `thumbHashKey` 由主文件放宽为 internal。
extension ClipboardCardFlowView {

    /// 预取前 12 条图片条目的缩略图（增量规格 2.2 第 4 条）
    ///
    /// 预取只负责「提前把并发额度用起来的头几条」；实际可见性仍由每条卡片首帧绘制时再请求兜底，
    /// 因此预取失败（闸门拒绝 / 解码失败）不会让任何卡片永久停在占位符号。
    func prefetchThumbnails() {
        var requested = 0
        for item in items where item.kind == .image {
            guard requested < Self.prefetchImageCount else { break }
            requested += 1
            ClipboardThumbnailLoader.shared.request(contentHash: item.contentHash, imagePath: item.imagePath)
        }
    }

    /// 订阅「缩略图就绪」：只对哈希命中的可见卡片淡入真图（不重建视图、不改选中态）
    func observeThumbnails() {
        thumbnailObserver = NotificationCenter.default.addObserver(
            forName: AppEvents.clipboardThumbnailReady, object: nil, queue: .main
        ) { [weak self] notification in
            guard let hash = notification.userInfo?[AppEvents.clipboardThumbnailHashKey] as? String else { return }
            Task { @MainActor in self?.handleThumbnailReady(contentHash: hash) }
        }
    }

    /// 缩略图就绪：先让命中卡片淡入真图，再为其余「可见且仍无缓存」的图片卡片续请求一次
    ///
    /// 续请求不可省：闸门只放行 3 个并发，首屏第 4 张起会被拒绝，若不在这里再次触发，
    /// 被拒卡片会一直停在占位符号。续请求同样只走 loader 路径，闸门自身去重与限流。
    func handleThumbnailReady(contentHash hash: String) {
        applyThumbnail(hash: hash)
        continueLoadingVisibleThumbnails()
    }

    /// 为可见且仍未缓存的图片卡片再请求一次（缓存命中由 loader 直接同步回调，不占闸门）
    func continueLoadingVisibleThumbnails() {
        for card in visibleCards() {
            guard let item = card.item, item.kind == .image else { continue }
            guard ClipboardCardView.thumbnailCache.object(forKey: item.contentHash as NSString) == nil else { continue }
            ClipboardThumbnailLoader.shared.request(contentHash: item.contentHash, imagePath: item.imagePath)
        }
    }

    /// 当前可见卡片（槽位超出窗口的复用视图一律排除；动效扩展要按可见卡片找删除对象）
    func visibleCards() -> [ClipboardCardView] {
        let count = visibleCount()
        return cardViews.prefix(count).filter { !$0.isHidden }
    }
}
