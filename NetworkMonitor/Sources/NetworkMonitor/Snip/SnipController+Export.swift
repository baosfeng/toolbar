import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 导出与落盘（从编排主类拆出，守住单文件门禁）

extension SnipController {

    // MARK: - 输出格式

    /// 当前输出格式（偏好 → 格式；缺失 / 未知按 PNG）
    var saveFormat: SnipImageFormat {
        SnipImageFormat.resolved(raw: storage.string(forKey: SnipPreferenceKey.saveFormat))
    }

    /// 当前 JPEG 质量（夹紧到 0.3…1.0，默认 0.9；PNG 时无意义）
    var jpegQuality: Double {
        SnipImageFormat.clampedQuality(
            storage.object(forKey: SnipPreferenceKey.jpegQuality) as? Double
                ?? SnipImageFormat.defaultJPEGQuality)
    }

    /// 按当前格式写盘（快速保存 / 自动保存 / 另存为 / 贴图保存共用这一份口径）
    func writeImage(_ image: CGImage, to url: URL) throws {
        try SnipFileWriter.write(image, to: url, format: saveFormat, quality: jpegQuality)
    }

// MARK: - 复制

    func copyToPasteboard(_ target: (captured: SnipCapturedImage, globalRect: CGRect),
                                  annotations: [SnipAnnotation] = []) {
        guard let cropped = composedImage(captured: target.captured,
                                          globalRect: target.globalRect,
                                          annotations: annotations) else {
            logger.warning("复制失败：选区裁剪为空")
            return
        }
        // 写入走 PNG 优先的多表示出口：裸 NSImage 只会写未压缩 TIFF（全屏 22.7 MB），
        // 既超过剪贴板历史单图上限（采不到这张图），也让其它 App 粘贴时解一张巨图。
        guard SnipPasteboardImageWriter.write(cropped, logger: logger) else {
            logger.warning("复制失败：写入系统剪贴板被拒")
            return
        }
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
            let url = directory.appendingPathComponent(SnipFileNaming.fileName(for: Date(), format: saveFormat))
            try writeImage(image, to: url)
            logger.info("已快速保存（\(saveFormat.displayName)）：\(LogRedaction.path(url.path))")
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
            let url = directory.appendingPathComponent(SnipFileNaming.fileName(for: Date(), format: saveFormat))
            try writeImage(image, to: url)
            logger.info("已自动保存（\(saveFormat.displayName)）：\(LogRedaction.path(url.path))")
        } catch {
            logger.warning("自动保存失败：\(error)")
        }
    }

    func presentSavePanel(for image: CGImage) {
        // 覆盖层已收掉：不自报家门时面板会开在别的 App 后面，用户只看到「按了保存什么都没发生」。
        // 这里只 activate（不切 .regular）——实测 `.accessory` 下 NSSavePanel 照样成为 key window、
        // 能正常接收键盘；切 `.regular` 会在 Dock 里闪出本应用图标，是用户报的「截图时 Dock 出现软件」的另一处。
        SnipForegroundPolicy.claimForeground()
        SnipForegroundPolicy.record(.savePanel)
        defer { restoreMenuBarPolicy() }
        let panel = NSSavePanel()
        // 只允许当前格式：早期这里写死 .png，用户选了 JPEG 也存不出 jpg
        panel.allowedContentTypes = [saveFormat.contentType]
        panel.nameFieldStringValue = SnipFileNaming.fileName(for: Date(), format: saveFormat)
        panel.directoryURL = SnipSaveDirectory.resolvedQuickSaveDirectory(storage: storage)
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else {
            logger.info("保存已取消")
            return
        }
        do {
            try writeImage(image, to: url)
            logger.info("已保存到（\(saveFormat.displayName)）：\(LogRedaction.path(url.path))")
        } catch {
            logger.error("保存失败：\(error)")
        }
    }
}
