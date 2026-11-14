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
        // 截图完成提示音（默认关；设置页「截图完成」一行开）
        onCaptureCompleted?()
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
        // 标注缩放比同样以捕获图实际像素 ÷ 屏幕点数推导：display.backingScale 来自
        // SnipDisplay.pixelSize，像素尺寸口径修正后两者一致，但仍以图像为准最稳。
        let scale = captured.display.frame.width > 0
            ? imageSize.width / captured.display.frame.width
            : captured.display.backingScale
        return SnipAnnotationComposer.compose(base: captured.image,
                                              cropRect: cropRect,
                                              annotations: annotations,
                                              selectionOrigin: localOrigin,
                                              scale: scale)
    }

    func saveQuickly(_ image: CGImage, annotations: [SnipAnnotation] = []) {
        // 跟随设置页的快速保存目录（未自定义时为默认目录）
        let directory = SnipSaveDirectory.resolvedQuickSaveDirectory(storage: storage)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(SnipFileNaming.fileName(for: Date()))
            try SnipFileWriter.writePNG(image, to: url)
            logger.info("已快速保存：\(LogRedaction.path(url.path))")
            dismissOverlays()
        } catch {
            fail(message: "保存失败：\(error.localizedDescription)")
        }
    }

    /// 复制后自动落盘：写进快速保存目录，失败只记日志（主流程是复制，不该被落盘失败打断）
    func persistQuietly(_ image: CGImage) {
        let directory = SnipSaveDirectory.resolvedQuickSaveDirectory(storage: storage)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(SnipFileNaming.fileName(for: Date()))
            try SnipFileWriter.writePNG(image, to: url)
            logger.info("已自动保存：\(LogRedaction.path(url.path))")
        } catch {
            logger.warning("自动保存失败：\(error)")
        }
    }

    func presentSavePanel(for image: CGImage) {
        // 覆盖层已收掉、激活策略也退回了菜单栏态：不自报家门时面板会开在别的 App 后面，
        // 用户只看到「按了保存什么都没发生」。这里显式切回可激活态并激活，面板关掉再退回。
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
        defer { restoreMenuBarPolicy() }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = SnipFileNaming.fileName(for: Date())
        panel.directoryURL = SnipSaveDirectory.resolvedQuickSaveDirectory(storage: storage)
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else {
            logger.info("保存已取消")
            return
        }
        do {
            try SnipFileWriter.writePNG(image, to: url)
            logger.info("已保存到：\(LogRedaction.path(url.path))")
        } catch {
            logger.error("保存失败：\(error)")
        }
    }
}
