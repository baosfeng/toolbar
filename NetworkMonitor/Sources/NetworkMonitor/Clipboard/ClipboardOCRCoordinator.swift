import CoreGraphics
import Foundation
import NetworkMonitorCore

// MARK: - 图片文字识别调度

/// 剪贴板图片文字识别的后台调度入口（采集后异步识别 → 回写 ocr_text → 通知面板刷新）
///
/// 线程模型（与缩略图管线同一范式，见 `ClipboardThumbnailLoader`）：
/// - `schedule` 只在主线程被采集回调调用：判定、登记、入队都是主线程状态，无锁；
/// - 解码（过像素守卫）+ Vision 识别在 `.utility` 的 detached task 上，不阻塞采集主路径；
/// - 回到主线程才写库与发事件（仓储线程安全，但事件订阅方在主线程）。
///
/// 三处判定各归其位：
/// - `ClipboardOCRPolicy.shouldRecognize`（Core）：开关 / 类型 / 路径 / 三态；
/// - `ClipboardOCRLoadGate`（Core）：并发 2 + 在途去重；
/// - `ClipboardOCRRetryPolicy`（Core）：失败冷却 60s + 最多 2 次，达上限写空结果转终态。
@MainActor
final class ClipboardOCRCoordinator {

    /// 识别器（协议注入：App 里是 VisionTextRecognizer）
    private let recognizer: any SnipTextRecognizing
    /// 结果回写（独立协议：只写 ocr_text 一列）
    private let repository: any ClipboardOCRRepository
    /// 开关真源（每次调度现读，关掉后新条目立即不再识别）
    private let preferences: ClipboardPreferences
    private let logger: LoggingService

    /// 并发与在途去重闸门
    private var gate = ClipboardOCRLoadGate()
    /// 失败重试策略（冷却 + 次数上限）
    private var retryPolicy = ClipboardOCRRetryPolicy()
    /// 世代号：`cancelAll` 递增后，之前入队的任务回调一律丢弃
    private var generation = 0

    init(recognizer: any SnipTextRecognizing,
         repository: any ClipboardOCRRepository,
         preferences: ClipboardPreferences,
         logger: LoggingService = AppContext.shared.logger) {
        self.recognizer = recognizer
        self.repository = repository
        self.preferences = preferences
        self.logger = logger
    }

    // MARK: 对外接口

    /// 请求识别一条（采集落库后调用；不满足条件时静默返回，不占闸门）
    func schedule(_ item: ClipboardItem) {
        guard ClipboardOCRPolicy.shouldRecognize(item, enabled: preferences.imageOCRRecognizeEnabled) else { return }
        guard let imagePath = item.imagePath, !imagePath.isEmpty else { return }
        let key = item.id.uuidString
        // 冷却未过直接跳过：同一条内容下次再被复制会重新走一遍判定，不需要定时器补排
        guard retryPolicy.shouldAttempt(key: key) else { return }
        guard gate.beginLoad(key: key) else { return }
        logger.debug("剪贴板图片文字识别入队：\(key.prefix(8))")

        let expectedGeneration = generation
        let recognizer = recognizer
        let logger = logger
        Task.detached(priority: .utility) { [weak self] in
            let outcome = await Self.recognize(imagePath: imagePath, recognizer: recognizer, logger: logger)
            await MainActor.run { [weak self] in
                self?.finish(item: item, key: key, generation: expectedGeneration, outcome: outcome)
            }
        }
    }

    /// 启动时补扫：库里仍有「未识别」的图片条目（上次退出时排到一半的）重新入队
    ///
    /// 只处理调用方给的当前条目集合，不做全表扫描（条数本来就由 maxItems 兜住）。
    func schedulePending(from items: [ClipboardItem]) {
        guard preferences.imageOCRRecognizeEnabled else { return }
        for item in items where ClipboardOCRPolicy.shouldRecognize(item, enabled: true) {
            schedule(item)
        }
    }

    /// 退出前丢弃在途回调（已入队的任务允许跑完，但结果不再写库）
    func cancelAll() {
        gate.reset()
        generation &+= 1
    }

    // MARK: 后台识别（不碰 AppKit / 数据库 / 通知）

    /// 一次识别的结果：成功（可能为空文本）或失败
    private enum Outcome: Sendable {
        /// 识别完成，text 为空串表示图上没有可读文字
        case finished(String)
        /// 识别失败（不可解码 / Vision 报错），交给冷却与次数上限收敛
        case failed
    }

    /// 后台：过像素守卫解码后做识别
    ///
    /// 尺寸守卫是「大图直接跳过」的唯一判据：`guardedCGImage` 解不开就记为失败，
    /// 由冷却与次数上限收敛（绝不硬解一张超出像素上限的图）。
    private nonisolated static func recognize(imagePath: String,
                                             recognizer: any SnipTextRecognizing,
                                             logger: LoggingService) async -> Outcome {
        guard let image = ClipboardImageDecoder.guardedCGImage(fromFileAt: imagePath) else {
            logger.warning("剪贴板图片文字识别跳过：原图不可解码或超出像素上限（\(LogRedaction.path(imagePath))）")
            return .failed
        }
        do {
            let lines = try await recognizer.recognize(in: SnipTextRecognitionImage(image: image))
            return .finished(ClipboardOCRPolicy.storedText(from: lines))
        } catch let error as SnipTextRecognitionError {
            // 「图里没有字」不是失败：它是确定的终态，直接落空串，不占冷却次数
            if case .noTextFound = error { return .finished("") }
            logger.warning("剪贴板图片文字识别失败：\(error)")
            return .failed
        } catch {
            logger.warning("剪贴板图片文字识别失败：\(error.localizedDescription)")
            return .failed
        }
    }

    // MARK: 主线程收尾

    /// 回到主线程统一收尾：归还额度 → 按结果写库 / 记失败 → 广播通知
    private func finish(item: ClipboardItem, key: String, generation expected: Int, outcome: Outcome) {
        // 已 cancelAll：reset 已清空在途登记，这里不能再 finishLoad（否则误删后来重新登记的同 key）
        guard expected == generation else { return }
        // 无论成败都先归还额度：失败若只记不还，闸门会被一个坏图永久占满
        gate.finishLoad(key: key)

        switch outcome {
        case .finished(let text):
            retryPolicy.markSucceeded(key: key)
            write(text: text, item: item)
        case .failed:
            retryPolicy.markFailed(key: key)
            let attempts = retryPolicy.failureCount(key: key)
            logger.warning("剪贴板图片文字识别失败（累计 \(attempts) 次）：\(key.prefix(8))")
            // 达上限：写空结果转终态，避免每次启动对一个坏图重试
            guard retryPolicy.isExhausted(key: key) else { return }
            logger.warning("剪贴板图片文字识别已达上限，标记为无文字：\(key.prefix(8))")
            write(text: "", item: item)
        }
    }

    /// 写回 ocr_text 并通知面板刷新
    private func write(text: String, item: ClipboardItem) {
        guard repository.updateClipboardItemOCRText(id: item.id, text: text) else {
            logger.warning("剪贴板图片文字识别结果未写入（条目可能已删除）：\(item.id.uuidString.prefix(8))")
            return
        }
        logger.info("剪贴板图片文字识别完成：\(item.id.uuidString.prefix(8))，\(text.count) 字")
        // 只发「某条识别就绪」事件：面板据此只刷新命中的详情区，不重排卡片、不动选中
        AppEvents.postClipboardOCRTextReady(itemID: item.id)
    }
}
