import AppKit
import NetworkMonitorCore

// MARK: - 剪贴板贴图（从编排主类拆出，守住单文件门禁）

extension SnipController {

    /// 把剪贴板内容贴到屏幕 — 图片、文件、颜色、HTML、文字都可以
    func pinFromClipboard() {
        let pasteboard = NSPasteboard.general
        let nsImage = NSImage(pasteboard: pasteboard)
        let filePaths = (pasteboard.readObjects(forClasses: [NSURL.self],
                                                options: [.urlReadingFileURLsOnly: true]) as? [URL])?
            .map(\.path) ?? []
        let plainText = pasteboard.string(forType: .string)
        let htmlData = pasteboard.data(forType: .html)
        let html = htmlData.flatMap { String(data: $0, encoding: .utf8) }

        guard let content = SnipClipboardClassifier.classify(hasImage: nsImage != nil,
                                                             filePaths: filePaths,
                                                             plainText: plainText,
                                                             html: html) else {
            logger.info("剪贴板里没有可贴的内容")
            return
        }

        if case .image = content,
           let nsImage,
           let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
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
    func pinClipboardItem(_ item: ClipboardItem) {
        if item.kind == .image,
           let path = item.imagePath,
           let image = NSImage(contentsOfFile: path),
           let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let screenScale = NSScreen.screens.first?.backingScaleFactor ?? 2
            let size = CGSize(width: CGFloat(cgImage.width) / screenScale,
                              height: CGFloat(cgImage.height) / screenScale)
            pinWindows.pin(image: cgImage, cgRect: placementRect(size: size))
            logger.info("已从历史贴图（图片）")
            return
        }
        let text = item.text ?? item.preview
        guard !text.isEmpty else {
            logger.info("该历史条目没有可贴的文本")
            return
        }
        guard let rendered = SnipClipboardRenderer.render(.text(text)) else { return }
        pinWindows.pin(image: rendered.image, cgRect: placementRect(size: rendered.size))
        logger.info("已从历史贴图（文本）")
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
