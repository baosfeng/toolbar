import AppKit
import NetworkMonitorCore

// MARK: - 缩略图后台解码

/// 剪贴板缩略图的后台解码入口（增量规格 2.2）
///
/// 线程模型：
/// - `request` 只允许主线程调用（卡片资源是无状态的纯查询路径，共享实例即可，不进组合根）；
/// - 解码在 `.utility` 后台队列（ImageIO 降采样，不展开原图位图）；
/// - 回来后才碰 AppKit / 缓存 / 通知：写 `ClipboardCardView.thumbnailCache`、调 completion、发 `AppEvents.clipboardThumbnailReady`。
///
/// 闸门判据全部在 Core 的 `ClipboardThumbnailLoadGate`（并发 3 + 在途去重 + 失败记忆），本类只做接线：
/// 闸门未通过时**不入队、不回调**，由后续重绘或通知再次触发；解码失败也归还额度，闸门不会被一次失败卡死。
@MainActor
final class ClipboardThumbnailLoader {

    /// 共享实例
    static let shared = ClipboardThumbnailLoader()

    /// 后台解码队列（.utility，避免与界面主线程抢资源）
    private let queue = DispatchQueue(label: "com.networkmonitor.clipboard.thumbnails", qos: .utility)

    /// 并发与在途去重闸门
    private var gate = ClipboardThumbnailLoadGate()

    /// 世代号：`cancelAll` 递增后，之前入队的任务回调一律丢弃
    private var generation = 0

    private let logger: LoggingService

    init(logger: LoggingService = AppContext.shared.logger) {
        self.logger = logger
    }

    // MARK: 对外接口

    /// 请求缩略图
    /// - Parameters:
    ///   - contentHash: 内容哈希（闸门与缓存键）
    ///   - imagePath: 原图路径（缩略图文件缺失时用它在后台补生成）
    ///   - completion: 解码完成回调（缓存命中时同步回调；未命中且闸门拒绝时不回调）
    func request(contentHash: String, imagePath: String?, completion: ((NSImage) -> Void)? = nil) {
        let hash = contentHash.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hash.isEmpty else { return }
        // 缓存命中：直接主线程回调，不占闸门
        if let cached = ClipboardCardView.thumbnailCache.object(forKey: hash as NSString) {
            completion?(cached)
            return
        }
        guard gate.beginLoad(hash: hash) else { return }
        let expectedGeneration = generation
        let logger = logger
        let box = completion.map { CompletionBox(handler: $0) }
        queue.async { [hash, imagePath, logger] in
            let decoded = Self.decode(hash: hash, imagePath: imagePath, logger: logger)
            Task { @MainActor [self] in
                self.finish(hash: hash, generation: expectedGeneration, decoded: decoded, box: box)
            }
        }
    }

    /// 清空在途登记：已入队任务允许跑完，但回调与通知一律丢弃（缓存与磁盘文件不删）
    func cancelAll() {
        gate.reset()
        generation &+= 1
    }

    // MARK: 后台解码（不碰 AppKit / 缓存 / 通知）

    /// 解码结果盒子：CGImage 是不可变数据，跨线程只读传递
    private struct Decoded: @unchecked Sendable {
        let image: CGImage
        let cost: Int
    }

    /// 读缩略图文件；缺失时用原图在后台补生成一次（与旧同步路径同一补生成逻辑）
    private static func decode(hash: String, imagePath: String?, logger: LoggingService) -> Decoded? {
        let url = ClipboardImageStore.thumbnailURL(for: hash)
        var cgImage = ClipboardImageDecoder.thumbnail(fromFileAt: url.path)
        if cgImage == nil, let imagePath, !imagePath.isEmpty,
           ClipboardImageStore.regenerateThumbnail(contentHash: hash, imagePath: imagePath, logger: logger) {
            cgImage = ClipboardImageDecoder.thumbnail(fromFileAt: url.path)
        }
        guard let cgImage else { return nil }
        // cost = 解码后像素字节数（与旧缓存口径一致）
        let cost = ClipboardImagePolicy.decodedBytes(width: cgImage.width, height: cgImage.height)
        return Decoded(image: cgImage, cost: cost)
    }

    // MARK: 主线程收尾

    /// 回到主线程后统一收尾：归还额度 → 写缓存 → 回调 → 广播通知
    private func finish(hash: String, generation expected: Int, decoded: Decoded?,
                        box: CompletionBox?) {
        // 已 cancelAll（面板收起）或世代已变：reset 已清空在途登记，这里不能再 finishLoad ——
        // 否则会误删「收起后又重新登记」的同 hash 在途，导致并发额度被提前归还。
        guard expected == generation else { return }
        // 无论成败都先归还额度：失败若只记不还，闸门会被一次坏文件永久占满
        gate.finishLoad(hash: hash)
        guard let decoded else {
            gate.markFailed(hash: hash)
            logger.warning("剪贴板缩略图解码失败（本会话内不再重试）：\(hash.prefix(8))")
            // 失败也广播：本事件同时承担「闸门空出一个额度」的信号，订阅方据此继续请求其余卡片，
            // 否则并发被失败占满时后续卡片会永久停在占位符号；失败哈希本身没有缓存，重绘只是重画占位。
            AppEvents.postClipboardThumbnailReady(contentHash: hash)
            return
        }
        let image = NSImage(cgImage: decoded.image,
                            size: NSSize(width: decoded.image.width, height: decoded.image.height))
        ClipboardCardView.thumbnailCache.setObject(image, forKey: hash as NSString, cost: decoded.cost)
        box?.handler(image)
        AppEvents.postClipboardThumbnailReady(contentHash: hash)
    }

    /// 回调盒子（跨线程搬运主线程闭包；Swift 并发里函数值不 Sendable）
    private final class CompletionBox: @unchecked Sendable {
        let handler: (NSImage) -> Void
        init(handler: @escaping (NSImage) -> Void) { self.handler = handler }
    }
}
