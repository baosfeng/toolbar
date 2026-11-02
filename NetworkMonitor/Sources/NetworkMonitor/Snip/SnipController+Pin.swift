import AppKit
import NetworkMonitorCore

// MARK: - 剪贴板贴图（从编排主类拆出，守住单文件门禁）

extension SnipController {

    /// 把剪贴板内容贴到屏幕 — 图片、文件、颜色、HTML、文字都可以
    ///
    /// 图片一律走 ImageIO 直读 CGImage（NSImage(pasteboard:) + cgImage(forProposedRect:)
    /// 会把整张位图展开，12000×12000 实测峰值 2764MB）；像素守卫拒绝时不贴图并记日志。
    func pinFromClipboard() {
        let pasteboard = NSPasteboard.general
        let clipboardImage = Self.clipboardCGImage(from: pasteboard)
        let filePaths = (pasteboard.readObjects(forClasses: [NSURL.self],
                                                options: [.urlReadingFileURLsOnly: true]) as? [URL])?
            .map(\.path) ?? []
        let plainText = pasteboard.string(forType: .string)
        let htmlData = pasteboard.data(forType: .html)
        let html = htmlData.flatMap { String(data: $0, encoding: .utf8) }

        let hasImage = clipboardImage.isImage
        guard let content = SnipClipboardClassifier.classify(hasImage: hasImage,
                                                             filePaths: filePaths,
                                                             plainText: plainText,
                                                             html: html) else {
            logger.info("剪贴板里没有可贴的内容")
            return
        }

        if case .image = content,
           clipboardImage.image == nil {
            // 剪贴板声称有图但守卫拒绝 / 解码失败：明确告知，而不是笼统地说「无法转成图像」
            logger.warning("剪贴板图片无法贴图：解码失败或超过像素上限")
            return
        }
        if case .image = content,
           let cgImage = clipboardImage.image {
            if pinWindows.restoreMatching(cgImage) { return }
            let screenScale = NSScreen.screens.first?.backingScaleFactor ?? 2
            let size = CGSize(width: CGFloat(cgImage.width) / screenScale,
                              height: CGFloat(cgImage.height) / screenScale)
            pinWindows.pin(image: cgImage, cgRect: placementRect(size: size))
            logger.info("已贴图（图片）")
            return
        }

        guard let rendered = SnipClipboardRenderer.render(content) else {
            logger.info("剪贴板内容无法转成图像")
            return
        }
        if pinWindows.restoreMatching(rendered.image) { return }
        pinWindows.pin(image: rendered.image, cgRect: placementRect(size: rendered.size))
        logger.info("已贴图（\(contentDescription(content))）")
    }

    /// 把剪贴板历史里的某一条贴到屏幕（右键卡片触发）
    ///
    /// 图片走 ImageIO 直读（先过像素守卫），解不出时沿用旧的文本占位回退，避免右键静默无反应。
    func pinClipboardItem(_ item: ClipboardItem) {
        if item.kind == .image, pinHistoricalImage(item) { return }
        let text = item.text ?? item.preview
        guard !text.isEmpty else {
            logger.info("该历史条目没有可贴的文本")
            return
        }
        guard let rendered = SnipClipboardRenderer.render(.text(text)) else { return }
        pinWindows.pin(image: rendered.image, cgRect: placementRect(size: rendered.size))
        logger.info("已从历史贴图（文本）")
    }

    // MARK: 图片读取

    /// 从系统剪贴板直读图片（PNG / TIFF 表示，ImageIO 解码 + 像素守卫）
    ///
    /// 只有文件 URL 时（Finder 里复制单张图片）沿用 NSImage(pasteboard:) 的旧语义：仍按图片贴，
    /// 但改走 ImageIO + 像素守卫，避免超大图把整张位图展开。
    /// - Returns: isImage 表示剪贴板是否声称有图（分类用），image 为守卫通过后的位图
    private static func clipboardCGImage(from pasteboard: NSPasteboard) -> (isImage: Bool, image: CGImage?) {
        if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff), !data.isEmpty {
            return (true, ClipboardImageDecoder.guardedCGImage(from: data))
        }
        // 文件 URL 兜底：只认能读出像素尺寸的第一项（非图片文件返回 nil，交给 .files 分支）
        let fileURLs = (pasteboard.readObjects(forClasses: [NSURL.self],
                                                options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        for fileURL in fileURLs {
            guard ClipboardImageDecoder.pixelSize(ofFileAt: fileURL.path) != nil else { continue }
            return (true, ClipboardImageDecoder.guardedCGImage(fromFileAt: fileURL.path))
        }
        return (false, nil)
    }

    /// 历史图片贴图（ImageIO 直读 + 像素守卫）
    /// - Returns: 是否已贴出；false 时调用方回退到文本占位
    private func pinHistoricalImage(_ item: ClipboardItem) -> Bool {
        guard let path = item.imagePath else { return false }
        guard let cgImage = ClipboardImageDecoder.guardedCGImage(fromFileAt: path) else {
            logger.warning("历史图片无法贴图：原图缺失、无法解码或超过像素上限")
            return false
        }
        let screenScale = NSScreen.screens.first?.backingScaleFactor ?? 2
        let size = CGSize(width: CGFloat(cgImage.width) / screenScale,
                          height: CGFloat(cgImage.height) / screenScale)
        pinWindows.pin(image: cgImage, cgRect: placementRect(size: size))
        logger.info("已从历史贴图（图片）")
        return true
    }

    /// 以鼠标位置为左上角，越界时朝屏幕内收
    private func placementRect(size: CGSize) -> CGRect {
        let mouse = NSEvent.mouseLocation
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let screenWidth = screen?.frame.width ?? 1440
        var origin = CGPoint(x: mouse.x, y: primaryHeight - mouse.y)
        if origin.x + size.width > screenWidth {
            origin.x = max(screenWidth - size.width - 20, 0)
        }
        if origin.y + size.height > primaryHeight {
            origin.y = max(primaryHeight - size.height - 20, 0)
        }
        return CGRect(origin: origin, size: size)
    }

    private func contentDescription(_ content: SnipClipboardContent) -> String {
        switch content {
        case .image: return "图片"
        case .files: return "文件"
        case .color: return "颜色"
        case .html: return "HTML"
        case .text: return "文本"
        }
    }
}
