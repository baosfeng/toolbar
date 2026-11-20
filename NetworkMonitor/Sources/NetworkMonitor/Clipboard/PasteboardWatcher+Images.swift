import AppKit
import NetworkMonitorCore

// MARK: - 剪贴板内容解析与图片结算（从 PasteboardWatcher 拆出，守住单文件体积上限）

/// `PasteboardWatcher` 的解析与结算部分 —— 主线程只交字节，其余都在 `ClipboardImagePipeline` 里
///
/// 拆文件原因：采集主文件贴着 15 KiB 上限，而「draft 解析 + 后台图片结算 + 超限降级」
/// 自成一套，独立成文件更清晰。跨文件访问：`pasteboard` / `logger` / `onCapture`
/// 由主文件放宽为 internal。
extension PasteboardWatcher {

    // MARK: 内容解析

    /// 采集解析的两条出路：文本类当场产出草稿，图片类只把字节交出去（结算在后台）
    enum DraftResolution {
        case immediate(ClipboardDraft)
        case deferred(ImageRequest)
    }

    /// 待后台结算的图片字节（主线程只负责读 pasteboard 与记录来源）
    struct ImageRequest: Sendable {
        /// 被选中的原始字节
        let data: Data
        /// 来源 App（取不到时 nil）
        let bundleID: String?
        let appName: String?
        /// 采集时刻（落库时间口径，与后台结算耗时无关）
        let now: Date
        /// 原始字节已超单图上限：结算时只读尺寸做占位降级，绝不落盘
        let isOversized: Bool
    }

    /// 按优先级解析：文件 URL > 图片 > RTF > 纯文本
    func makeDraft(source: NSRunningApplication?) -> DraftResolution? {
        let bundleID = source?.bundleIdentifier
        let appName = source?.localizedName
        let pasteboardItems = pasteboard.pasteboardItems ?? []
        let now = Date()

        // 1) 文件 URL（多个文件合并为一条记录）：text 存原始路径，preview 存分类摘要
        let paths = pasteboardItems
            .compactMap { $0.string(forType: .fileURL) }
            .compactMap { URL(string: $0)?.path }
        if !paths.isEmpty, let payload = ClipboardContentHasher.prepareText(paths.joined(separator: "\n")) {
            return .immediate(ClipboardDraft(kind: .file,
                                  contentHash: payload.contentHash,
                                  text: payload.text,
                                  preview: ClipboardFileSummary.summarize(paths: paths, fallbackText: payload.text),
                                  sourceBundleID: bundleID,
                                  sourceAppName: appName,
                                  createdAt: now))
        }

        // 2) 图片（按 ClipboardImageFormat 候选顺序取首个可读表示，同一表示用于哈希与落盘）
        //    字节在这里读、结算在 ClipboardImagePipeline：主线程不碰哈希 / 落盘 / 缩略图
        if let request = makeImageRequest(pasteboardItems: pasteboardItems, bundleID: bundleID, appName: appName, now: now) {
            return .deferred(request)
        }

        // 3) RTF（模型不存富文本字节，落纯文本正文）
        if let rtfData = pasteboard.data(forType: .rtf),
           let attributed = NSAttributedString(rtf: rtfData, documentAttributes: nil),
           let payload = ClipboardContentHasher.prepareText(attributed.string) {
            return .immediate(ClipboardDraft(kind: .rtf,
                                  contentHash: payload.contentHash,
                                  text: payload.text,
                                  preview: ClipboardPreview.make(from: payload.text),
                                  sourceBundleID: bundleID,
                                  sourceAppName: appName,
                                  createdAt: now))
        }

        // 4) 纯文本：多个 pasteboardItems 按换行拼接为一条记录
        var texts = pasteboardItems.compactMap { $0.string(forType: .string) }
        if texts.isEmpty, let text = pasteboard.string(forType: .string) { texts = [text] }
        guard let payload = ClipboardContentHasher.prepareText(texts.joined(separator: "\n")) else { return nil }
        return .immediate(ClipboardDraft(kind: .text,
                              contentHash: payload.contentHash,
                              text: payload.text,
                              preview: ClipboardPreview.make(from: payload.text),
                              sourceBundleID: bundleID,
                              sourceAppName: appName,
                              createdAt: now))
    }

    /// 图片条目：多个 pasteboardItems 只取首个可解码项
    ///
    /// 这里只选字节，哈希 / 像素守卫 / 落盘 / 缩略图交给 `ClipboardImagePipeline`。
    /// 旧实现按字节上限直接 `continue`：全屏截图（裸 TIFF 22MB）在历史里整条消失，
    /// 且原因是 debug 级日志、默认不落盘。现在超限交后台产出「原图过大未保存」的占位。
    private func makeImageRequest(pasteboardItems: [NSPasteboardItem],
                                  bundleID: String?,
                                  appName: String?,
                                  now: Date) -> ImageRequest? {
        Self.imageRequest(pasteboardItems: pasteboardItems,
                          bundleID: bundleID,
                          appName: appName,
                          now: now,
                          logger: logger)
    }

    /// 图片请求解析的纯函数入口
    ///
    /// 取舍口径全在 Core 的 `ClipboardImageCandidateSelection`（可被 TestRunner 直接断言）：
    /// 优先取不超过单图上限的候选，全部超限时取第一个并标 `isOversized` 走占位降级。
    static func imageRequest(pasteboardItems: [NSPasteboardItem],
                             bundleID: String?,
                             appName: String?,
                             now: Date,
                             logger: LoggingService) -> ImageRequest? {
        let candidates = pasteboardItems.compactMap { Self.imageRepresentation(of: $0) }
        guard let selection = ClipboardImageCandidateSelection.select(candidates: candidates,
                                                                      maxBytes: ClipboardLimit.maxImageBytes) else { return nil }
        if selection.isOversized {
            // info 级：这是用户能感知的降级（历史里是一条「原图过大未保存」的占位），要能事后查到
            logger.info("剪贴板图片原始字节超过单图上限，改为占位记录（不落盘）")
        }
        return ImageRequest(data: selection.data,
                            bundleID: bundleID,
                            appName: appName,
                            now: now,
                            isOversized: selection.isOversized)
    }

    /// 按 ClipboardImageFormat 候选顺序取首个可读表示（同一次复制只取一种）
    ///
    /// 候选 = 白名单八类 + 白名单外图片类型兜底，前两项仍是 PNG / TIFF，既有语义不变；
    /// 落盘扩展名仍由字节真实类型决定，像素守卫在落盘前生效。
    private static func imageRepresentation(of pasteboardItem: NSPasteboardItem) -> ClipboardImageFormat.Selection? {
        let typeNames = pasteboardItem.types.map(\.rawValue)
        return ClipboardImageFormat.firstReadableCandidate(
            in: typeNames,
            read: { pasteboardItem.data(forType: NSPasteboard.PasteboardType($0)) }
        )
    }

    // MARK: 后台结算

    /// 主线程只交字节，哈希 / 落盘 / 缩略图 / 编码都在后台流水线里（见 ClipboardImagePipeline）
    func submitImage(_ request: ImageRequest) {
        let logger = logger
        Task { [weak self] in
            guard let result = await ClipboardImagePipeline.shared.process(data: request.data,
                                                                          isOversized: request.isOversized,
                                                                          logger: logger) else { return }
            self?.deliver(imageResult: result, request: request)
        }
    }

    /// 回主线程产出 draft：成功走已落盘路径，像素守卫 / 字节超限拒绝走占位降级（文案由拒绝原因给出）
    ///
    /// 顺序由 `ClipboardImagePipeline`（actor）保证：连续两次复制按到达顺序结算，
    /// 不会出现「后复制的先落库」把列表顺序打乱。
    func deliver(imageResult: ClipboardImagePipeline.Result, request: ImageRequest) {
        let draft: ClipboardDraft
        switch imageResult.outcome {
        case .stored(let stored):
            draft = ClipboardDraft(kind: .image,
                                   contentHash: imageResult.contentHash,
                                   preview: "图片 \(stored.width)×\(stored.height)",
                                   imagePath: stored.path,
                                   imageWidth: stored.width,
                                   imageHeight: stored.height,
                                   sourceBundleID: request.bundleID,
                                   sourceAppName: request.appName,
                                   createdAt: request.now)
        case .rejected(let rejection):
            // 占位降级：图太大（像素炸弹 / 原始字节超限）或不合法时只记尺寸与提示，绝不落盘、不缓存
            draft = ClipboardDraft(kind: .image,
                                   contentHash: imageResult.contentHash,
                                   preview: rejection.placeholderPreview,
                                   imagePath: nil,
                                   imageWidth: rejection.width,
                                   imageHeight: rejection.height,
                                   sourceBundleID: request.bundleID,
                                   sourceAppName: request.appName,
                                   createdAt: request.now)
        case nil:
            return
        }
        onCapture?(draft)
    }
}
