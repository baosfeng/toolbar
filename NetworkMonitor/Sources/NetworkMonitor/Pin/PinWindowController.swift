import AppKit
import NetworkMonitorCore

// MARK: - 贴图窗口集合

/// 贴图窗口管理 — 位置换算、关闭恢复、隐藏全部、色卡
@MainActor
final class PinWindowController {

    /// 关闭后可恢复的张数上限（与 Snipaste 默认一致）
    static let maximumRecoverable = 3

    private let logger: LoggingService
    /// 偏好存储（解析快速保存目录用，禁止直读 UserDefaults）
    private let storage: any KeyValueStorage
    private var windows: [PinWindow] = []
    private var recentlyClosed: [ClosedPin] = []
    private(set) var isHidden = false

    /// 关闭但未销毁的贴图
    private struct ClosedPin {
        let image: CGImage
        let frame: CGRect
        let scale: CGFloat
    }

    var count: Int { windows.count }

    /// 屏幕参数变化监听
    private var screenObserver: NSObjectProtocol?

    init(logger: LoggingService = AppContext.shared.logger,
         storage: any KeyValueStorage = AppContext.shared.storage) {
        self.logger = logger
        self.storage = storage
        // 自己监听屏幕变化，省得编排层再转一道
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.clampToScreens() }
        }
    }

    // MARK: - 贴图

    /// 直接贴一张图到指定全局位置
    @discardableResult
    func pin(image: CGImage, cgRect: CGRect) -> PinWindow {
        let window = makeWindow(image: image, appKitRect: appKitRect(for: cgRect))
        windows.append(window)
        window.orderFrontRegardless()
        window.makeKey()
        logger.info("已贴图 \(Int(window.frame.width))×\(Int(window.frame.height))，当前共 \(windows.count) 张")
        return window
    }

    /// 把捕获图中的选区裁出来贴到屏幕
    @discardableResult
    func pin(captured: SnipCapturedImage, cgRect: CGRect) -> PinWindow? {
        let imageSize = CGSize(width: captured.image.width, height: captured.image.height)
        let pixelRect = SelectionGeometry.pixelRect(of: cgRect, in: captured.display, imageSize: imageSize)
        guard pixelRect.width >= 1, pixelRect.height >= 1,
              let cropped = captured.image.cropping(to: pixelRect) else {
            logger.warning("贴图裁剪失败，选区不在捕获图范围内：\(cgRect)")
            return nil
        }
        return pin(image: cropped, cgRect: cgRect)
    }

    /// 颜色卡片：把颜色值贴成一个色块窗口
    @discardableResult
    func pinColor(_ color: NSColor, cgRect: CGRect) -> PinWindow? {
        let size = CGSize(width: 120, height: 90)
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        return pin(image: cgImage, cgRect: cgRect)
    }

    // MARK: - 隐藏全部

    func toggleHidden() {
        isHidden.toggle()
        for window in windows {
            if isHidden {
                window.orderOut(nil)
            } else {
                window.orderFrontRegardless()
            }
        }
        logger.info(isHidden ? "已隐藏全部贴图（\(windows.count) 张）" : "已恢复显示贴图")
    }

    // MARK: - 关闭恢复

    /// 剪贴板内容与某张已关闭贴图一致时，按原位置恢复它
    @discardableResult
    func restoreMatching(_ image: CGImage) -> Bool {
        guard let index = recentlyClosed.firstIndex(where: {
            $0.image.width == image.width && $0.image.height == image.height
        }) else {
            return false
        }
        let closed = recentlyClosed.remove(at: index)
        let window = makeWindow(image: closed.image, appKitRect: closed.frame)
        window.setScale(closed.scale)
        windows.append(window)
        window.orderFrontRegardless()
        window.makeKey()
        logger.info("已恢复关闭的贴图，当前共 \(windows.count) 张")
        return true
    }

    /// 若最近关闭过一张贴图，就按原位置恢复
    @discardableResult
    func restoreLastClosed() -> Bool {
        guard !recentlyClosed.isEmpty else { return false }
        let closed = recentlyClosed.removeFirst()
        let window = makeWindow(image: closed.image, appKitRect: closed.frame)
        window.setScale(closed.scale)
        windows.append(window)
        window.orderFrontRegardless()
        window.makeKey()
        logger.info("已恢复关闭的贴图，当前共 \(windows.count) 张")
        return true
    }

    /// 屏幕增删或分辨率变化后，把跑到屏幕外的贴图收回来
    func clampToScreens() {
        let union = NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
        guard !union.isNull else { return }
        for window in windows {
            var frame = window.frame
            if !union.intersects(frame) {
                // 整块跑到屏幕外：挪到主屏左上角附近
                frame.origin = CGPoint(x: union.minX + 80, y: union.maxY - frame.height - 80)
            } else {
                frame.origin.x = min(max(frame.origin.x, union.minX), max(union.maxX - frame.width, union.minX))
                frame.origin.y = min(max(frame.origin.y, union.minY), max(union.maxY - frame.height, union.minY))
            }
            window.setFrame(frame, display: true)
        }
    }

    func pruneClosed() {
        windows.removeAll { !$0.isVisible }
    }

    func closeAll() {
        for window in windows {
            window.close()
        }
        windows.removeAll()
        recentlyClosed.removeAll()
    }

    // MARK: - 内部

    private func makeWindow(image: CGImage, appKitRect: CGRect) -> PinWindow {
        let window = PinWindow(image: image, initialSize: appKitRect.size)
        window.setFrame(appKitRect, display: true)
        window.onClosed = { [weak self] closedWindow, destroyed in
            self?.handleClosed(closedWindow, destroyed: destroyed)
        }
        window.onCopy = { [weak self] source in
            self?.copyImage(from: source)
        }
        window.onSave = { [weak self] source in
            self?.saveImage(from: source)
        }
        return window
    }

    private func handleClosed(_ window: PinWindow, destroyed: Bool) {
        windows.removeAll { $0 === window }
        guard !destroyed else {
            logger.info("已销毁一张贴图，剩余 \(windows.count) 张")
            return
        }
        recentlyClosed.insert(ClosedPin(image: window.currentImage,
                                        frame: window.frame,
                                        scale: window.currentScale),
                              at: 0)
        if recentlyClosed.count > Self.maximumRecoverable {
            recentlyClosed.removeLast()
        }
        logger.info("已关闭一张贴图（可恢复），剩余 \(windows.count) 张")
    }

    private func copyImage(from window: PinWindow) {
        let image = NSImage(cgImage: window.currentImage,
                            size: NSSize(width: window.currentImage.width,
                                         height: window.currentImage.height))
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        logger.info("已复制贴图")
    }

    private func saveImage(from window: PinWindow) {
        // 跟随设置页的快速保存目录（未自定义时为默认目录）
        let directory = SnipSaveDirectory.resolvedQuickSaveDirectory(storage: storage)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = SnipFileNaming.fileName(for: Date())
        panel.directoryURL = directory
        panel.canCreateDirectories = true
        // 贴图窗口在 screenSaver 层级，先让开避免盖住面板
        window.orderOut(nil)
        let response = panel.runModal()
        window.orderFrontRegardless()
        guard response == .OK, let url = panel.url else { return }
        do {
            try SnipFileWriter.writePNG(window.currentImage, to: url)
            logger.info("贴图已保存：\(url.path)")
        } catch {
            logger.error("贴图保存失败：\(error)")
        }
    }

    /// 从捕获图中裁出选区像素（跨屏时只取与该屏交叠部分）
    static func crop(_ captured: SnipCapturedImage, to cgRect: CGRect) -> CGImage? {
        let imageSize = CGSize(width: captured.image.width, height: captured.image.height)
        let pixelRect = SelectionGeometry.pixelRect(of: cgRect, in: captured.display, imageSize: imageSize)
        guard pixelRect.width >= 1, pixelRect.height >= 1 else { return nil }
        return captured.image.cropping(to: pixelRect)
    }

    private func appKitRect(for cgRect: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return SelectionGeometry.appKitRect(fromCG: cgRect, primaryHeight: primaryHeight)
    }
}
