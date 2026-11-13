#if DEBUG
import AppKit
import NetworkMonitorCore

// MARK: - 剪贴板快照取证：图片卡首帧占位 → 缩略图就绪 → 删除确认提示

/// 剪贴板面板三项增量的离屏取证（**仅 DEBUG**，release 构建不含本文件）
///
/// 触发：`NM_SNAPSHOT_CLIPBOARD_EVIDENCE=1 NM_SNAPSHOT_DIR=/tmp/<dir> <可执行>`
/// 产出三张 640×260、浅色 PNG（画布口径与 `SnapshotClipboardPanel` 一致）：
/// 1. `panel-clipboard-image-firstframe.png`：首帧（缓存空 → 图片卡仍是 photo 占位符号）
/// 2. `panel-clipboard-image-ready.png`：后台解码写回缓存后再画（真实缩略图）
/// 3. `panel-clipboard-delete-hint.png`：提示行显示删除二次确认文案
///
/// 图片夹具不是假路径：用真实 PNG 字节算出内容哈希，按 `ClipboardImageStore` 的落盘约定写入
/// `<hash>.png` 与 `<hash>_thumb.png`，因此取证走的是与真机同一条链路
/// （`ClipboardThumbnailLoader` → `ClipboardCardView.thumbnailCache` → 哈希级重绘）。
@MainActor
enum SnapshotClipboardEvidence {

    /// 取证开关（与 `NM_SNAPSHOT_DIR` 组合使用；不设置时不产出任何图）
    static let envKey = "NM_SNAPSHOT_CLIPBOARD_EVIDENCE"

    /// 画布尺寸（与 07-contract 的剪贴板画布一致）
    private static let canvasSize = NSSize(width: 640, height: 260)

    /// 等缩略图就绪的上限（后台解码是毫秒级；取 3 秒留足余量）
    private static let readyTimeout: TimeInterval = 3

    /// 取证入口：未开开关立即返回；开关打开时同步夹具 → 三张图依次落盘
    static func captureIfRequested(directory: URL) async {
        guard ProcessInfo.processInfo.environment[envKey]?.isEmpty == false else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            AppContext.shared.logger.error("剪贴板取证目录创建失败：\(error.localizedDescription)")
            return
        }
        let logger = AppContext.shared.logger
        guard let items = makeFixtureItems(evidenceDirectory: directory, logger: logger) else {
            logger.error("剪贴板取证夹具构建失败（真实 PNG 字节或哈希不可用）")
            return
        }

        // 首帧口径的前提：缓存必须是空的，否则第一张图会直接画到真缩略图
        ClipboardCardView.thumbnailCache.removeAllObjects()

        let hashes = items.filter(\.isImage).map(\.contentHash)
        let firstFrame = makeCanvas(items: items, hint: nil)
        MenuPanelSnapshot.render(view: firstFrame, size: canvasSize,
                                 appearanceName: .aqua,
                                 to: directory.appendingPathComponent("panel-clipboard-image-firstframe.png"))
        let cachedAtFirstFrame = cachedHashes(hashes)

        await waitForThumbnails(hashes: hashes)

        let ready = makeCanvas(items: items, hint: nil)
        MenuPanelSnapshot.render(view: ready, size: canvasSize,
                                 appearanceName: .aqua,
                                 to: directory.appendingPathComponent("panel-clipboard-image-ready.png"))
        let cachedAfter = cachedHashes(hashes)

        // 提示行只走产品自己的 showHint 通道，文案常量取自 ClipboardDeleteHint.single
        let hintView = makeCanvas(items: items, hint: ClipboardDeleteHint.single)
        MenuPanelSnapshot.render(view: hintView, size: canvasSize,
                                 appearanceName: .aqua,
                                 to: directory.appendingPathComponent("panel-clipboard-delete-hint.png"))

        writeStatus(directory: directory, items: items, hashes: hashes,
                    cachedAtFirstFrame: cachedAtFirstFrame, cachedAfter: cachedAfter, logger: logger)
    }

    // MARK: - 画布

    /// 复用产品自己的剪贴板画布（材质底 14pt 圆角 + ClipboardPanelView），只额外灌提示行文案
    private static func makeCanvas(items: [ClipboardItem], hint: String?) -> NSView {
        let canvas = SnapshotClipboardPanel(size: canvasSize, items: items).makeView()
        if let hint {
            canvas.subviews.compactMap { $0 as? ClipboardPanelView }.first?.showHint(hint)
        }
        return canvas
    }

    // MARK: - 缩略图就绪等待

    /// 轮询缓存直到两张图片卡的缩略图都写回（或超时）；超时即已知限制，由结论如实记录
    private static func waitForThumbnails(hashes: [String]) async {
        let deadline = Date().addingTimeInterval(readyTimeout)
        while Date() < deadline {
            if cachedHashes(hashes).count == hashes.count { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    /// 已进缓存的哈希数（缓存命中才是「真缩略图」的判据，卡片绘制路径只读缓存）
    private static func cachedHashes(_ hashes: [String]) -> Set<String> {
        Set(hashes.filter { ClipboardCardView.thumbnailCache.object(forKey: $0 as NSString) != nil })
    }

    // MARK: - 夹具

    /// 组装 2 条图片条目 + 2 条文本条目（图片走真实落盘目录与真实内容哈希）
    private static func makeFixtureItems(evidenceDirectory: URL, logger: LoggingService) -> [ClipboardItem]? {
        let now = Date()
        guard let first = makePNGData(label: "图片 A", colors: [.systemTeal, .systemBlue],
                                     size: NSSize(width: 512, height: 384)),
              let second = makePNGData(label: "图片 B", colors: [.systemOrange, .systemPink],
                                      size: NSSize(width: 400, height: 400)) else { return nil }
        var items: [ClipboardItem] = []
        for (index, data) in [first, second].enumerated() {
            guard let hash = ClipboardContentHasher.prepareImageData(data),
                  let size = ClipboardImageDecoder.pixelSize(of: data),
                  let path = ensureImageFiles(data: data, hash: hash,
                                                evidenceDirectory: evidenceDirectory,
                                                index: index + 1, logger: logger) else { return nil }
            items.append(ClipboardItem(kind: .image,
                                       preview: "图片 \(size.width)×\(size.height)",
                                       imagePath: path,
                                       imageWidth: size.width,
                                       imageHeight: size.height,
                                       contentHash: hash,
                                       sourceBundleID: "com.apple.Safari",
                                       sourceAppName: "Safari",
                                       copyCount: 2,
                                       isPinned: index == 0,
                                       createdAt: now.addingTimeInterval(-120)))
        }
        let texts = ("curl -I https://api.example.com/v1/status", "把这段命令贴进终端后回车",
                     "终端", "备忘录")
        items.append(ClipboardItem(kind: .text, text: texts.0, preview: texts.0,
                                   contentHash: hashOf(text: texts.0) ?? "text-fixture-1",
                                   sourceBundleID: "com.apple.Terminal", sourceAppName: texts.2,
                                   createdAt: now.addingTimeInterval(-600)))
        items.append(ClipboardItem(kind: .text, text: texts.1, preview: texts.1,
                                   contentHash: hashOf(text: texts.1) ?? "text-fixture-2",
                                   sourceBundleID: "com.apple.Notes", sourceAppName: texts.3,
                                   createdAt: now.addingTimeInterval(-1800)))
        return items
    }

    /// 文本哈希（与采集侧同一口径：规范化后 UTF-8 SHA256）
    private static func hashOf(text: String) -> String? {
        ClipboardContentHasher.hash(text: text)
    }

    /// 按 ClipboardImageStore 的落盘约定写入原图与缩略图；文件被孤儿清扫删掉时按需补写
    private static func ensureImageFiles(data: Data, hash: String, evidenceDirectory: URL,
                                        index: Int, logger: LoggingService) -> String? {
        let directory = ClipboardImageStore.directory
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            logger.error("剪贴板取证图片目录创建失败：\(error.localizedDescription)")
            return nil
        }
        let original = ClipboardImageStore.originalURL(for: hash, fileExtension: "png")
        if !FileManager.default.fileExists(atPath: original.path) {
            do {
                try data.write(to: original, options: .atomic)
            } catch {
                logger.error("剪贴板取证原图写入失败：\(error.localizedDescription)")
                return nil
            }
        }
        let thumbnail = ClipboardImageStore.thumbnailURL(for: hash)
        if !FileManager.default.fileExists(atPath: thumbnail.path) {
            ClipboardImageStore.writeThumbnail(data: data, to: thumbnail, logger: logger)
        }
        // 启动 5s 后的孤儿清扫会删掉真实目录里的夹具（DB 里没有对应记录），落盘即留档到证据目录
        archive(original, to: evidenceDirectory.appendingPathComponent("fixture-image-\(index).png"))
        if FileManager.default.fileExists(atPath: thumbnail.path) {
            archive(thumbnail, to: evidenceDirectory.appendingPathComponent("fixture-image-\(index)-thumb.png"))
        }
        return original.path
    }

    /// 覆盖式留档一份文件（失败只记 debug，不阻断取证）
    private static func archive(_ source: URL, to target: URL) {
        try? FileManager.default.removeItem(at: target)
        try? FileManager.default.copyItem(at: source, to: target)
    }

    /// 造一张真实 PNG（渐变底 + 文字标签），用作图片条目的原始字节
    private static func makePNGData(label: String, colors: [NSColor], size: NSSize) -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGradient(colors: colors)?.draw(in: NSRect(origin: .zero, size: size), angle: 90)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 30, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let text = label as NSString
        let textSize = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: (size.width - textSize.width) / 2,
                              y: (size.height - textSize.height) / 2),
                  withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: - 自证文本

    /// 写一份状态文本，避免结论只靠肉眼：缓存命中情况 + 夹具路径 + 文案口径
    private static func writeStatus(directory: URL, items: [ClipboardItem], hashes: [String],
                                   cachedAtFirstFrame: Set<String>, cachedAfter: Set<String>,
                                   logger: LoggingService) {
        let image = items.filter(\.isImage)
        let text = """
        fixture_original = \(image.first?.imagePath ?? "—")
        image_hashes = \(hashes.map { String($0.prefix(12)) }.joined(separator: ","))
        image_kinds = \(image.count) 条图片 / \(items.count - image.count) 条文本
        cached_at_first_frame = \(cachedAtFirstFrame.count) / \(hashes.count)
        cached_after_wait = \(cachedAfter.count) / \(hashes.count)
        counts_label = \(ClipboardPanelFooterText.countsLabel(total: items.count, pinned: items.filter(\.isPinned).count))
        delete_hint = \(ClipboardDeleteHint.single)
        """ + "\n"
        let url = directory.appendingPathComponent("panel-clipboard-evidence-status.txt")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            logger.warning("剪贴板取证状态写入失败：\(error.localizedDescription)")
        }
        logger.info("剪贴板取证完成：首帧缓存 \(cachedAtFirstFrame.count)/\(hashes.count)，就绪后 \(cachedAfter.count)/\(hashes.count)")
    }
}
#endif
