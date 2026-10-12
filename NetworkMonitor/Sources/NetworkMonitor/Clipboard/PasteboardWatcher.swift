import AppKit
import NetworkMonitorCore

// MARK: - 采集服务实现

/// 剪贴板采集器 — 同一个实现的两种模式（设计规格第 6 节分支 A / B）
///
/// - 模式 B（polling，当前默认）：500ms Timer 轮询 + changeCount 变更即读
/// - 模式 A（onDemand）：不启动轮询，仅在打开面板或点击「采集当前剪贴板」时调 captureNow()
///
/// 两种模式共用同一条流水线：changeCount 判定 → 访问权限判定 → 忽略判定 → 哈希 → 落盘 → onCapture。
/// 落库与事件通知由调用方（组合根）在 onCapture 回调里完成，采集器不直接触碰仓储。
@MainActor
final class PasteboardWatcher: ClipboardCaptureService {

    /// 轮询间隔（设计规格第 5 节：500ms）
    static let pollInterval: TimeInterval = 0.5

    private let preferences: ClipboardPreferences
    private let logger: LoggingService
    private let pasteboard: NSPasteboard

    private var timer: Timer?
    /// 上次读到的 changeCount；初值取哨兵值，避免在初始化阶段读取剪贴板（探针未覆盖的路径不做多余访问）
    private var lastChangeCount = Int.min

    private(set) var isRunning = false
    var onStateChange: ((ClipboardCaptureState) -> Void)?
    var onCapture: ((ClipboardDraft) -> Void)?

    init(preferences: ClipboardPreferences,
         logger: LoggingService = AppContext.shared.logger,
         pasteboard: NSPasteboard = .general) {
        self.preferences = preferences
        self.logger = logger
        self.pasteboard = pasteboard
    }

    // MARK: ClipboardCaptureService

    func start() {
        guard !isRunning else { return }
        guard preferences.captureMode == .polling else {
            // 分支 A：不轮询，退化为「打开面板读一次 + 面板内手动采集」
            logger.info("剪贴板采集启动：分支 A（按需），不启动后台轮询")
            onStateChange?(.stopped)
            return
        }
        guard checkAccessBehavior() else { return }

        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.capture() }
        }
        // 加入 RunLoop 的 common modes：菜单展开 / 拖拽期间也不停止采集
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        isRunning = true
        onStateChange?(.running)
        logger.info("剪贴板采集启动：分支 B（500ms 轮询）")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        guard isRunning else { return }
        isRunning = false
        onStateChange?(.stopped)
        logger.info("剪贴板采集已停止")
    }

    /// 立即采集一次（分支 A 的面板打开 / 手动采集按钮；与轮询同一条流水线，无新内容时静默返回）
    func captureNow() {
        capture()
    }

    // MARK: 采集流水线

    private func capture() {
        guard checkAccessBehavior() else { return }
        let changeCount = pasteboard.changeCount
        // 第 5 节第 2 步：changeCount 未变立即返回，不读任何内容数据（含类型列表）
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        let typeNames = (pasteboard.types ?? []).map(\.rawValue)
        let source = sourceApplication()
        if let reason = ClipboardIgnorePolicy.ignoreReason(typeNames: typeNames,
                                                           bundleID: source?.bundleIdentifier,
                                                           blacklistedBundleIDs: preferences.ignoredBundleIDs) {
            logger.debug("剪贴板采集跳过：\(reason.label)")
            return
        }
        guard let draft = makeDraft(source: source) else {
            logger.debug("剪贴板无可用内容（空内容 / 图片超限 / 无支持类型）")
            return
        }
        onCapture?(draft)
    }

    /// 读取系统剪贴板访问行为；alwaysDeny 时停采并提示（不得静默）
    private func checkAccessBehavior() -> Bool {
        guard #available(macOS 15.4, *) else { return true }
        guard pasteboard.accessBehavior == .alwaysDeny else { return true }
        stop()
        onStateChange?(.denied(.alwaysDeny))
        logger.warning("剪贴板访问被系统拒绝：请前往「系统设置 → 隐私与安全性」允许本应用访问剪贴板")
        return false
    }

    /// 来源 App：前台应用即用户的复制来源；前台是本 App 时不记录来源（面板打开态的采集）
    private func sourceApplication() -> NSRunningApplication? {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return nil }
        if let ownBundleID = Bundle.main.bundleIdentifier, frontmost.bundleIdentifier == ownBundleID {
            return nil
        }
        return frontmost
    }

    // MARK: 内容解析

    /// 按优先级解析：文件 URL > 图片 > RTF > 纯文本
    private func makeDraft(source: NSRunningApplication?) -> ClipboardDraft? {
        let bundleID = source?.bundleIdentifier
        let appName = source?.localizedName
        let pasteboardItems = pasteboard.pasteboardItems ?? []
        let now = Date()

        // 1) 文件 URL（多个文件合并为一条记录）
        let paths = pasteboardItems
            .compactMap { $0.string(forType: .fileURL) }
            .compactMap { URL(string: $0)?.path }
        if !paths.isEmpty, let payload = ClipboardContentHasher.prepareText(paths.joined(separator: "\n")) {
            return ClipboardDraft(kind: .file,
                                  contentHash: payload.contentHash,
                                  text: payload.text,
                                  preview: ClipboardPreview.make(from: payload.text),
                                  sourceBundleID: bundleID,
                                  sourceAppName: appName,
                                  createdAt: now)
        }

        // 2) 图片（PNG 优先、TIFF 兜底，同一表示同时用于哈希与落盘）
        if let imageDraft = makeImageDraft(pasteboardItems: pasteboardItems, bundleID: bundleID, appName: appName, now: now) {
            return imageDraft
        }

        // 3) RTF（模型不存富文本字节，落纯文本正文）
        if let rtfData = pasteboard.data(forType: .rtf),
           let attributed = NSAttributedString(rtf: rtfData, documentAttributes: nil),
           let payload = ClipboardContentHasher.prepareText(attributed.string) {
            return ClipboardDraft(kind: .rtf,
                                  contentHash: payload.contentHash,
                                  text: payload.text,
                                  preview: ClipboardPreview.make(from: payload.text),
                                  sourceBundleID: bundleID,
                                  sourceAppName: appName,
                                  createdAt: now)
        }

        // 4) 纯文本：多个 pasteboardItems 按换行拼接为一条记录
        var texts = pasteboardItems.compactMap { $0.string(forType: .string) }
        if texts.isEmpty, let text = pasteboard.string(forType: .string) { texts = [text] }
        guard let payload = ClipboardContentHasher.prepareText(texts.joined(separator: "\n")) else { return nil }
        return ClipboardDraft(kind: .text,
                              contentHash: payload.contentHash,
                              text: payload.text,
                              preview: ClipboardPreview.make(from: payload.text),
                              sourceBundleID: bundleID,
                              sourceAppName: appName,
                              createdAt: now)
    }

    /// 图片条目：多个 pasteboardItems 只取首个可解码项
    private func makeImageDraft(pasteboardItems: [NSPasteboardItem],
                                bundleID: String?,
                                appName: String?,
                                now: Date) -> ClipboardDraft? {
        for pasteboardItem in pasteboardItems {
            guard let representation = Self.imageRepresentation(of: pasteboardItem) else { continue }
            guard let contentHash = ClipboardContentHasher.prepareImageData(representation.data) else {
                logger.debug("图片为空或超过上限，跳过落库")
                continue
            }
            guard let stored = ClipboardImageStore.store(data: representation.data,
                                                         contentHash: contentHash,
                                                         logger: logger) else { continue }
            return ClipboardDraft(kind: .image,
                                  contentHash: contentHash,
                                  preview: "图片 \(stored.width)×\(stored.height)",
                                  imagePath: stored.path,
                                  imageWidth: stored.width,
                                  imageHeight: stored.height,
                                  sourceBundleID: bundleID,
                                  sourceAppName: appName,
                                  createdAt: now)
        }
        return nil
    }

    /// PNG 优先、缺失或不合法时兜底 TIFF；同一次复制只取一种表示
    private static func imageRepresentation(of pasteboardItem: NSPasteboardItem) -> (data: Data, isPNG: Bool)? {
        if let png = pasteboardItem.data(forType: .png) { return (png, true) }
        if let tiff = pasteboardItem.data(forType: .tiff) { return (tiff, false) }
        return nil
    }
}

// MARK: - 图片落盘

/// 图片落盘工具 — 原图与缩略图共用内容哈希命名
///
/// - 原图：~/Library/Application Support/macMonitor/clipboard/images/<hash>.png
/// - 缩略图：<hash>_thumb.png（最长边 320，等比缩放）
enum ClipboardImageStore {

    /// 缩略图最长边
    static let thumbnailMaxEdge: CGFloat = 320

    /// 落盘结果
    struct Stored {
        /// 原图路径
        let path: String
        /// 像素宽
        let width: Int
        /// 像素高
        let height: Int
    }

    /// 图片目录
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("macMonitor/clipboard/images", isDirectory: true)
    }

    /// 缩略图路径（卡片视图懒加载用）
    static func thumbnailURL(for contentHash: String) -> URL {
        directory.appendingPathComponent("\(contentHash)_thumb.png")
    }

    /// 原图落盘并生成缩略图
    /// - Parameter data: 被选中表示的原始字节（PNG 或 TIFF）
    static func store(data: Data, contentHash: String, logger: LoggingService) -> Stored? {
        let directory = Self.directory
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let fileURL = directory.appendingPathComponent("\(contentHash).png")
            try data.write(to: fileURL, options: .atomic)
            guard let image = NSImage(contentsOf: fileURL) else {
                logger.warning("剪贴板图片无法解码，已跳过：\(contentHash.prefix(8))")
                return nil
            }
            let size = pixelSize(of: image)
            writeThumbnail(image: image, to: thumbnailURL(for: contentHash), logger: logger)
            return Stored(path: fileURL.path, width: Int(size.width), height: Int(size.height))
        } catch {
            logger.error("剪贴板图片落盘失败：\(error.localizedDescription)")
            return nil
        }
    }

    /// 像素尺寸（优先取位图表示，避免受点/像素比影响）
    private static func pixelSize(of image: NSImage) -> NSSize {
        if let representation = image.representations.first,
           representation.pixelsWide > 0, representation.pixelsHigh > 0 {
            return NSSize(width: representation.pixelsWide, height: representation.pixelsHigh)
        }
        return image.size
    }

    /// 生成缩略图（最长边 320，等比缩放）
    private static func writeThumbnail(image: NSImage, to url: URL, logger: LoggingService) {
        guard let tiff = image.tiffRepresentation,
              let source = NSBitmapImageRep(data: tiff) else { return }
        let pixelWidth = CGFloat(max(source.pixelsWide, 1))
        let pixelHeight = CGFloat(max(source.pixelsHigh, 1))
        let scale = min(1, thumbnailMaxEdge / max(pixelWidth, pixelHeight))
        let target = NSSize(width: max(1, (pixelWidth * scale).rounded()),
                            height: max(1, (pixelHeight * scale).rounded()))
        guard let thumbnail = NSBitmapImageRep(bitmapDataPlanes: nil,
                                               pixelsWide: Int(target.width),
                                               pixelsHigh: Int(target.height),
                                               bitsPerSample: 8,
                                               samplesPerPixel: 4,
                                               hasAlpha: true,
                                               isPlanar: false,
                                               colorSpaceName: .deviceRGB,
                                               bytesPerRow: 0,
                                               bitsPerPixel: 0) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: thumbnail)
        image.draw(in: NSRect(origin: .zero, size: target), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        guard let png = thumbnail.representation(using: .png, properties: [:]) else { return }
        do {
            try png.write(to: url, options: .atomic)
        } catch {
            logger.warning("剪贴板缩略图写入失败：\(error.localizedDescription)")
        }
    }
}
