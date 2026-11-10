#if DEBUG
import AppKit
import NetworkMonitorCore
import ScreenCaptureKit

// MARK: - 覆盖层可见性自证（仅 DEBUG）

/// 覆盖层出现后立即用 ScreenCaptureKit 拍屏并落盘，供人核对覆盖层是否真的在屏幕上
///
/// 触发方式：NM_SNIP_VISIBLE_PROBE=1
/// 产物：/tmp/nm-overlay-visible.png
@MainActor
enum SnipVisibleProbe {

    static let envKey = "NM_SNIP_VISIBLE_PROBE"
    static let outputPath = "/tmp/nm-overlay-visible.png"

    static var isRequested: Bool {
        ProcessInfo.processInfo.environment[envKey] != nil
    }

    /// 覆盖层就绪后延时一拍再抓屏（等首帧落屏）
    static func capture(after delay: UInt64 = 800_000_000, logger: LoggingService) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: delay)
            do {
                guard let display = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true).displays.first else {
                    logger.warning("可见性自证：取不到屏幕")
                    return
                }
                let image: CGImage
                if #available(macOS 15.2, *) {
                    image = try await SCScreenshotManager.captureImage(in: display.frame)
                } else {
                    let filter = SCContentFilter(display: display, excludingWindows: [])
                    let configuration = SCStreamConfiguration()
                    configuration.width = Int(display.frame.width) * 2
                    configuration.height = Int(display.frame.height) * 2
                    image = try await SCScreenshotManager.captureImage(contentFilter: filter,
                                                                       configuration: configuration)
                }
                let rep = NSBitmapImageRep(cgImage: image)
                guard let data = rep.representation(using: .png, properties: [:]) else { return }
                try data.write(to: URL(fileURLWithPath: outputPath))
                logger.info("可见性自证：已写入 \(outputPath)")
            } catch {
                logger.warning("可见性自证失败：\(error)")
            }
        }
    }
}
#endif
