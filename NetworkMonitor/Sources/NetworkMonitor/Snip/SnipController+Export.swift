import AppKit
import NetworkMonitorCore

// MARK: - 导出与落盘（从编排主类拆出，守住单文件门禁）

extension SnipController {

// MARK: - 复制

    func copyToPasteboard(_ target: (captured: SnipCapturedImage, globalRect: CGRect),
                                  annotations: [SnipAnnotation] = []) {
        guard let cropped = composedImage(captured: target.captured,
                                          globalRect: target.globalRect,
                                          annotations: annotations) else {
            logger.warning("复制失败：选区裁剪为空")
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let image = NSImage(cgImage: cropped, size: target.globalRect.size)
        pasteboard.writeObjects([image])
        logger.info("已复制选区 \(Int(target.globalRect.width))×\(Int(target.globalRect.height))")
    }

    // MARK: - 保存

    /// 把标注烧进裁剪图；没有标注时等价于纯裁剪
    func composedImage(captured: SnipCapturedImage,
                               globalRect: CGRect,
                               annotations: [SnipAnnotation]) -> CGImage? {
        let imageSize = CGSize(width: captured.image.width, height: captured.image.height)
        let cropRect = SelectionGeometry.pixelRect(of: globalRect,
                                                   in: captured.display,
                                                   imageSize: imageSize)
        let localOrigin = CGPoint(x: globalRect.minX - captured.display.frame.minX,
                                  y: globalRect.minY - captured.display.frame.minY)
        return SnipAnnotationComposer.compose(base: captured.image,
                                              cropRect: cropRect,
                                              annotations: annotations,
                                              selectionOrigin: localOrigin,
                                              scale: captured.display.backingScale)
    }

    func saveQuickly(_ image: CGImage, annotations: [SnipAnnotation] = []) {
        // 跟随设置页的快速保存目录（未自定义时为默认目录）
        let directory = SnipSaveDirectory.resolvedQuickSaveDirectory(storage: storage)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(SnipFileNaming.fileName(for: Date()))
            try SnipFileWriter.writePNG(image, to: url)
            logger.info("已快速保存：\(url.path)")
            dismissOverlays()
        } catch {
            logger.error("快速保存失败：\(error)")
        }
    }

    func presentSavePanel(for image: CGImage) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = SnipFileNaming.fileName(for: Date())
        panel.directoryURL = SnipSaveDirectory.resolvedQuickSaveDirectory(storage: storage)
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try SnipFileWriter.writePNG(image, to: url)
            logger.info("已保存到：\(url.path)")
        } catch {
            logger.error("保存失败：\(error)")
        }
    }
}
