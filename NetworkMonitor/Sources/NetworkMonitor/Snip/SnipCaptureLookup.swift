import AppKit
import NetworkMonitorCore
import NetworkMonitorFeatureSnip

// MARK: - 覆盖层 → 捕获图 / 选区的解析（从编排主类拆出，守住单文件门禁）

/// 复制 / 保存 / 贴图 / OCR 四条输出链路共用同一套「这个覆盖层对应哪张捕获图」的口径。
/// 拆出主文件的理由：主类已经贴着 500 行 / 15 KiB 门禁，而这段是完整的独立职责。
extension SnipController {

    /// 放宽为 internal：OCR 扩展文件要用（与复制 / 保存同一套选区解析口径）
    func capturedFor(_ view: SnipOverlayView) -> SnipCapturedImage? {
        // 在「所有创建过的窗口」里找：被新一批顶替的旧窗口不在 overlays 里，
        // 只在 overlays 里找会让这些窗口上的复制 / 保存静默失败（点了没反应）。
        let window = spawnedOverlays.first { $0.overlayView === view }
            ?? overlays.first { $0.overlayView === view }
        guard let window else { return nil }
        // 配对走 displayID（frame 会因取整 / 缩放漂移，浮点相等配不上）
        return SnipCaptureMatching.capture(forDisplayID: window.displayID,
                                           frame: window.frame,
                                           in: captures)
    }

    /// 放宽为 internal：OCR 扩展文件要用（本地点选区 → 捕获图 + 全局矩形）
    func resolve(capturedFor view: SnipOverlayView,
                 localRect: CGRect) -> (captured: SnipCapturedImage, globalRect: CGRect)? {
        guard let captured = capturedFor(view) else {
            logger.warning("找不到覆盖层对应的捕获图")
            return nil
        }
        let global = localRect.offsetBy(dx: captured.display.frame.minX,
                                        dy: captured.display.frame.minY)
        guard global.width >= 1, global.height >= 1 else { return nil }
        return (captured, global)
    }
}
