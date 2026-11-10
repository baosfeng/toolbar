#if DEBUG
import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 截图覆盖层离屏取证（仅 DEBUG）

/// 把「暗化 + 选区 + 标注 + 工具条」整屏渲染成 PNG，供人核对覆盖层实际长相
///
/// 触发方式：`NM_SNIP_OVERLAY_SNAPSHOT_DIR=/tmp/nm-snip-overlay-shot <可执行>`
/// 产物：`overlay-selected.png` / `overlay-idle.png`
///
/// 为什么不用真机拍屏：覆盖层跑在 screenSaver 层级，锁屏 / 息屏时拍不到；
/// 离屏渲染与真实窗口走同一份 `draw`，排版与配色等价，可离线核对。
@MainActor
enum SnipOverlaySnapshot {

    static let directoryEnvKey = "NM_SNIP_OVERLAY_SNAPSHOT_DIR"
    private static let canvasSize = NSSize(width: 1000, height: 620)

    static func runIfRequested() {
        guard let path = ProcessInfo.processInfo.environment[directoryEnvKey], !path.isEmpty else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            let directory = URL(fileURLWithPath: path, isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            renderToFile(at: directory.appendingPathComponent("overlay-idle.png"), phase: .idle)
            renderToFile(at: directory.appendingPathComponent("overlay-selected.png"), phase: .selected)
            NSApp.terminate(nil)
        }
    }

    private enum Phase { case idle, selected }

    private static func renderToFile(at url: URL, phase: Phase) {
        guard let backdrop = makeBackdropImage() else { return }
        let view = SnipOverlayView(frame: NSRect(origin: .zero, size: canvasSize),
                                   screenshot: backdrop,
                                   windowInfos: [],
                                   displayOrigin: .zero,
                                   lastSelection: nil,
                                   history: [])
        switch phase {
        case .idle:
            view.debugHover(atLocalPoint: CGPoint(x: 480, y: 300))
        case .selected:
            view.debugApplySelection(CGRect(x: 220, y: 150, width: 560, height: 340))
            view.debugAddAnnotation(SnipAnnotation(kind: .rectangle,
                                                   start: CGPoint(x: 265, y: 195),
                                                   end: CGPoint(x: 455, y: 300),
                                                   style: SnipAnnotationStyle(color: .red, lineWidth: 3)))
            view.debugAddAnnotation(SnipAnnotation(kind: .arrow,
                                                   start: CGPoint(x: 470, y: 300),
                                                   end: CGPoint(x: 660, y: 420),
                                                   style: SnipAnnotationStyle(color: .orange, lineWidth: 3)))
            view.debugAddAnnotation(SnipAnnotation(kind: .text,
                                                   start: CGPoint(x: 280, y: 430),
                                                   end: CGPoint(x: 280, y: 430),
                                                   text: "标注随截图一起复制",
                                                   style: SnipAnnotationStyle(color: .green, lineWidth: 3)))
        }

        let container = SnapshotBackdropView(frame: NSRect(origin: .zero, size: canvasSize))
        container.appearance = NSAppearance(named: .darkAqua)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: canvasSize),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = container
        window.appearance = container.appearance
        view.frame = NSRect(origin: .zero, size: canvasSize)
        container.addSubview(view)

        container.layoutSubtreeIfNeeded()
        view.needsDisplay = true
        container.needsDisplay = true
        view.displayIfNeeded()
        container.displayIfNeeded()

        let pixelWidth = max(1, Int(canvasSize.width.rounded()))
        let pixelHeight = max(1, Int(canvasSize.height.rounded()))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: pixelWidth,
                                         pixelsHigh: pixelHeight,
                                         bitsPerSample: 8,
                                         samplesPerPixel: 4,
                                         hasAlpha: true,
                                         isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0,
                                         bitsPerPixel: 0) else {
            AppContext.shared.logger.error("覆盖层取证位图创建失败")
            return
        }
        rep.size = canvasSize
        container.cacheDisplay(in: container.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        do {
            try data.write(to: url)
            AppContext.shared.logger.info("覆盖层取证已写入 \(url.lastPathComponent) \(pixelWidth)x\(pixelHeight)")
        } catch {
            AppContext.shared.logger.error("覆盖层取证写入失败：\(error)")
        }
    }

    /// 造一张有层次感的桌面底图（渐变 + 网格 + 两个「窗口」矩形）
    private static func makeBackdropImage() -> CGImage? {
        let width = Int(canvasSize.width)
        let height = Int(canvasSize.height)
        let space = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space,
                                      bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                                          | CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        let colors = [CGColor(red: 0.10, green: 0.16, blue: 0.26, alpha: 1),
                      CGColor(red: 0.26, green: 0.32, blue: 0.44, alpha: 1)] as CFArray
        if let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
            context.drawLinearGradient(gradient,
                                       start: CGPoint(x: 0, y: CGFloat(height)),
                                       end: CGPoint(x: CGFloat(width), y: 0),
                                       options: [])
        }
        context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.08))
        context.setLineWidth(1)
        for x in stride(from: 0, through: width, by: 40) {
            context.move(to: CGPoint(x: CGFloat(x), y: 0))
            context.addLine(to: CGPoint(x: CGFloat(x), y: CGFloat(height)))
        }
        for y in stride(from: 0, through: height, by: 40) {
            context.move(to: CGPoint(x: 0, y: CGFloat(y)))
            context.addLine(to: CGPoint(x: CGFloat(width), y: CGFloat(y)))
        }
        context.strokePath()
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.14))
        context.fill(CGRect(x: 40, y: 60, width: 380, height: 240))
        context.fill(CGRect(x: 620, y: 330, width: 330, height: 200))
        return context.makeImage()
    }
}
#endif
