import AppKit
import NetworkMonitorCore

// MARK: - 缩略图后台解码

/// 剪贴板缩略图的后台解码入口（增量规格 2.2 / 第三批 A2）
///
/// 线程模型：
/// - `request` 只允许主线程调用（卡片资源是无状态的纯查询路径，共享实例即可，不进组合根）；
/// - 解码在 `.utility` 后台队列（ImageIO 降采样，不展开原图位图）；
/// - 回来后才碰 AppKit / 缓存 / 通知：写 `ClipboardCardView.thumbnailCache`、调 completion、发 `AppEvents.clipboardThumbnailReady`。
///
/// 两处判定各归其位：
/// - `ClipboardThumbnailLoadGate`（Core）：并发 3 + 在途去重；未通过时不入队、不回调；
/// - `ClipboardThumbnailRetryPolicy`（Core）：失败冷却 30s + 最多 3 次的上限，到期自动重新请求，
///   一个坏文件不会再让该哈希整个会话停在占位符号。
@MainActor
final class ClipboardThumbnailLoader {

    /// 共享实例
    static let shared = ClipboardThumbnailLoader()

    /// 后台解码队列（.utility，避免与界面主线程抢资源）
    private let queue = DispatchQueue(label: "com.networkmonitor.clipboard.thumbnails", qos: .utility)

    /// 并发与在途去重闸门
    private var gate = ClipboardThumbnailLoadGate()

    /// 失败重试策略（冷却 + 次数上限；「本会话内不再重试」由它唯一判定）
    private var retryPolicy = ClipboardThumbnailRetryPolicy()

    /// 冷却到期后的重新请求（同一时刻只排一个，取最近到期的那个）
    private var retryWorkItem: DispatchWorkItem?

    /// 冷却中的待重试项（hash → 原图路径），到期后统一重发一次请求
    private var pendingRetries: [String: PendingRetry] = [:]

    /// 一条待重试项
    private struct PendingRetry {
        /// 原图路径（缩略图缺失时用于补生成）
        let imagePath: String?
    }

    /// 世代号：`cancelAll` 递增后，之前入队的任务回调一律丢弃
    private var generation = 0

    /// 缩略图最长边（与 Core 默认值同源）
    private let maxPixelEdge = ClipboardImagePolicy.thumbnailMaxEdge

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
        // 失败过就按策略判定：冷却未过返回 false 并排一次到期重试，达上限则就此放弃
        if !retryPolicy.shouldRetry(hash: hash) {
            scheduleRetryIfNeeded(hash: hash, imagePath: imagePath)
            return
        }
        guard gate.beginLoad(hash: hash) else { return }
        let expectedGeneration = generation
        let logger = logger
        let edge = maxPixelEdge
        let box = completion.map { CompletionBox(handler: $0) }
        queue.async { [hash, imagePath, logger, edge] in
            let decoded = Self.decode(hash: hash, imagePath: imagePath, maxPixelEdge: edge, logger: logger)
            Task { @MainActor [self] in
                self.finish(hash: hash, generation: expectedGeneration, decoded: decoded, box: box)
            }
        }
    }

    /// 清空在途登记与排期：已入队任务允许跑完，但回调与通知一律丢弃（缓存与磁盘文件不删）
    ///
    /// 失败记录**不清**：冷却与终态是会话级状态，面板开合不该让一个坏文件重新走满 3 次重试；
    /// 面板重开时的请求仍由 `shouldRetry` 判定（冷却已过就重试，终态则不再尝试）。
    func cancelAll() {
        gate.reset()
        retryWorkItem?.cancel()
        retryWorkItem = nil
        pendingRetries.removeAll()
        generation &+= 1
    }

    // MARK: 重试排期

    /// 把冷却中的哈希记进待重试队列，并按最近的到期时间重排一次定时器
    ///
    /// 无冷却时段的实现细节：定时器只负责「到期后把队列里的项重新 request 一遍」，
    /// 是否真的放行仍由策略的 `shouldRetry` 决定，两处口径不会打架。
    private func scheduleRetryIfNeeded(hash: String, imagePath: String?) {
        guard retryPolicy.retryDelay(hash: hash) != nil else {
            // 终态：达次数上限，本会话不再尝试（也不留占位排期）
            pendingRetries.removeValue(forKey: hash)
            logger.debug("剪贴板缩略图重试已达上限，本会话不再尝试：\(hash.prefix(8))")
            return
        }
        // 已在队列里就不重排：卡片重绘会高频调用本方法，每次都重建定时器等于自造抖动
        guard pendingRetries[hash] == nil else { return }
        pendingRetries[hash] = PendingRetry(imagePath: imagePath)
        // 按队列里最紧迫的那一项排期（其余项到期后由策略重新判定，仍冷却中的会再排一轮）
        let offsets = pendingRetries.keys.compactMap { retryPolicy.retryDelay(hash: $0) }
        guard let nearest = offsets.min() else { return }
        retryWorkItem?.cancel()
        let generation = generation
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.retryAfterCooldown(generation: generation) }
        }
        retryWorkItem = work
        queue.asyncAfter(deadline: .now() + max(nearest, 0.1), execute: work)
    }

    /// 冷却到期：把待重试项逐个重新请求一遍（仍冷却中的会再次排期）
    private func retryAfterCooldown(generation expected: Int) {
        guard expected == generation else { return }
        retryWorkItem = nil
        let waiting = pendingRetries
        pendingRetries.removeAll()
        for (hash, pending) in waiting {
            request(contentHash: hash, imagePath: pending.imagePath)
        }
        // 补一次「额度已释放」信号：闸门满时上面的请求会被拒，不在途的卡片就不会再自己续请求；
        // 通知带上其中一个哈希即可，订阅方收到后只做「重绘命中卡片 + 续请求其余可见卡片」。
        if let anyHash = waiting.keys.first {
            AppEvents.postClipboardThumbnailReady(contentHash: anyHash)
        }
    }

    // MARK: 后台解码（不碰 AppKit / 缓存 / 通知）

    /// 解码结果盒子：CGImage 是不可变数据，跨线程只读传递
    private struct Decoded: @unchecked Sendable {
        let image: CGImage
        let cost: Int
    }

    /// 读缩略图文件；缺失时用原图在后台补生成一次（与旧同步路径同一补生成逻辑）
    private nonisolated static func decode(hash: String, imagePath: String?, maxPixelEdge: Int,
                               logger: LoggingService) -> Decoded? {
        let url = ClipboardImageStore.thumbnailURL(for: hash)
        var cgImage = ClipboardImageDecoder.thumbnail(fromFileAt: url.path, maxPixelSize: maxPixelEdge)
        // 兜底一级：ImageIO 打不开缩略图文件时，改用 NSBitmapImageRep 直读同一份字节，
        // 解出的 CGImage 仍走上面同一个降采样出口，不新增第二套缩放实现
        if cgImage == nil {
            cgImage = fallbackThumbnail(atPath: url.path, maxPixelEdge: maxPixelEdge, logger: logger)
        }
        if cgImage == nil, let imagePath, !imagePath.isEmpty,
           ClipboardImageStore.regenerateThumbnail(contentHash: hash, imagePath: imagePath, logger: logger) {
            cgImage = ClipboardImageDecoder.thumbnail(fromFileAt: url.path, maxPixelSize: maxPixelEdge)
            if cgImage == nil {
                cgImage = fallbackThumbnail(atPath: url.path, maxPixelEdge: maxPixelEdge, logger: logger)
            }
        }
        // 最后一级：缩略图与其补生成都失败时，直接对原图走兜底解码
        // （ImageIO 不认、NSBitmapImageRep 能认的格式，例如某些老 TIFF / PSD）
        if cgImage == nil, let imagePath, !imagePath.isEmpty {
            cgImage = fallbackThumbnail(atPath: imagePath, maxPixelEdge: maxPixelEdge, logger: logger)
        }
        guard let cgImage else { return nil }
        // cost = 解码后像素字节数（与旧缓存口径一致）
        let cost = ClipboardImagePolicy.decodedBytes(width: cgImage.width, height: cgImage.height)
        return Decoded(image: cgImage, cost: cost)
    }

    /// ImageIO 失败后的兜底解码：NSBitmapImageRep → CGImage → 既有降采样出口
    ///
    /// 调用方只会在主路径已失败时进来，因此这里只做一次字节→位图的直读；
    /// 原图字节先过像素守卫，避免兜底路把像素炸弹解开。
    private nonisolated static func fallbackThumbnail(atPath path: String, maxPixelEdge: Int,
                                          logger: LoggingService) -> CGImage? {
        guard !path.isEmpty, let data = FileManager.default.contents(atPath: path), !data.isEmpty else {
            return nil
        }
        guard let size = ClipboardImageDecoder.pixelSize(of: data),
              ClipboardImagePolicy.isAllowed(width: size.width, height: size.height) else {
            logger.debug("剪贴板缩略图兜底解码被像素守卫拒绝：\(LogRedaction.path(path))")
            return nil
        }
        guard let rep = NSBitmapImageRep(data: data), let full = rep.cgImage else {
            logger.debug("剪贴板缩略图兜底解码仍失败：\(LogRedaction.path(path))")
            return nil
        }
        return ClipboardImageDecoder.thumbnail(from: full, maxPixelSize: maxPixelEdge)
    }

    // MARK: 主线程收尾

    /// 回到主线程后统一收尾：归还额度 → 写缓存 / 记失败 → 回调 → 广播通知
    private func finish(hash: String, generation expected: Int, decoded: Decoded?,
                        box: CompletionBox?) {
        // 已 cancelAll（面板收起）或世代已变：reset 已清空在途登记，这里不能再 finishLoad ——
        // 否则会误删「收起后又重新登记」的同 hash 在途，导致并发额度被提前归还。
        guard expected == generation else { return }
        // 无论成败都先归还额度：失败若只记不还，闸门会被一次坏文件永久占满
        gate.finishLoad(hash: hash)
        guard let decoded else {
            retryPolicy.markFailed(hash: hash)
            logger.warning("剪贴板缩略图解码失败（累计 \(retryPolicy.failureCount(hash: hash)) 次）：\(hash.prefix(8))")
            if retryPolicy.isExhausted(hash: hash) {
                logger.warning("剪贴板缩略图重试已达上限，本会话不再尝试：\(hash.prefix(8))")
            }
            // 失败也广播：本事件同时承担「闸门空出一个额度」的信号，订阅方据此继续请求其余卡片，
            // 否则并发被失败占满时后续卡片会永久停在占位符号；失败哈希本身没有缓存，重绘只是重画占位。
            AppEvents.postClipboardThumbnailReady(contentHash: hash)
            return
        }
        // 成功即清空失败记录与待重试项：同一哈希之后再次请求会重新走一次完整流程
        retryPolicy.markSucceeded(hash: hash)
        pendingRetries.removeValue(forKey: hash)
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
