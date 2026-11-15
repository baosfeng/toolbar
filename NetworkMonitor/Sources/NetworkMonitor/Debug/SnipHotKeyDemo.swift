#if DEBUG
import AppKit
import NetworkMonitorCore

// MARK: - 截图热键取证钩子（仅 DEBUG）

/// 截图相关的两个「摆状态 + 截图取证」钩子 — **仅 DEBUG**，release 构建完全不包含本文件
///
/// 从 `SnipController+HotKeys.swift` 迁到这里，与其它调试钩子（`SnipDemo` /
/// `SnipOverlaySnapshot` / `SnipCropProbe`）同一处收口：热键注册文件只留热键注册，
/// 取证逻辑一律在 `Debug/` 下。
///
/// 触发：
/// - `NM_SNIP_OVERLAY_DEMO=1` 摆出覆盖层 + 选区 + 各种标注，落两张图
/// - `NM_SNIP_WHITEBOARD_DEMO=1` 进白板并落一张图
extension SnipController {

    /// 仅 DEBUG：NM_SNIP_OVERLAY_DEMO=1 时直接摆出覆盖层 + 选区并截图取证
    func runOverlayDemoIfRequested() {
        guard ProcessInfo.processInfo.environment["NM_SNIP_OVERLAY_DEMO"] != nil else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            do {
                let result = try await captureService.captureAllDisplays()
                captures = result
                presentOverlays(result)
                // 先取证窗口检测高亮
                overlays.first?.overlayView.debugPointerFrozen = true
                overlays.first?.overlayView.debugHover(atLocalPoint: CGPoint(x: 600, y: 330))
                try? await Task.sleep(nanoseconds: 900_000_000)
                if let hoverImage = try await captureService.captureAllDisplays().first?.image {
                    try SnipDemo.saveImage(hoverImage, to: "/tmp/nm-snip-hover.png")
                    print("demo: 已写入 /tmp/nm-snip-hover.png")
                }
                // 再取证选区态
                overlays.first?.overlayView.debugApplySelection(CGRect(x: 300, y: 300, width: 600, height: 400))
                overlays.first?.overlayView.debugOpenPanel(.tools(SnipTool.overflow))
                overlays.first?.overlayView.debugAddAnnotation(
                    SnipAnnotation(kind: .rectangle,
                                   start: CGPoint(x: 340, y: 340),
                                   end: CGPoint(x: 560, y: 460),
                                   style: SnipAnnotationStyle(color: .red, lineWidth: 4)))
                overlays.first?.overlayView.debugAddAnnotation(
                    SnipAnnotation(kind: .arrow,
                                   start: CGPoint(x: 620, y: 420),
                                   end: CGPoint(x: 820, y: 560),
                                   style: SnipAnnotationStyle(color: .blue, lineWidth: 4)))
                overlays.first?.overlayView.debugAddAnnotation(
                    SnipAnnotation(kind: .polyline,
                                   start: CGPoint(x: 620, y: 320),
                                   end: CGPoint(x: 860, y: 400),
                                   points: [CGPoint(x: 620, y: 320),
                                            CGPoint(x: 720, y: 380),
                                            CGPoint(x: 800, y: 330),
                                            CGPoint(x: 860, y: 400)],
                                   style: SnipAnnotationStyle(color: .green, lineWidth: 4)))
                var rotatedText = SnipAnnotation(kind: .text,
                                                 start: CGPoint(x: 400, y: 640),
                                                 end: CGPoint(x: 400, y: 640),
                                                 text: "缩放 1.3× 且旋转 20° 的文字",
                                                 style: SnipAnnotationStyle(color: .red, lineWidth: 4))
                rotatedText.fontScale = 1.3
                rotatedText.rotation = .pi / 9
                overlays.first?.overlayView.debugAddAnnotation(rotatedText)
                overlays.first?.overlayView.debugAddAnnotation(
                    SnipAnnotation(kind: .mosaic,
                                   start: CGPoint(x: 380, y: 560),
                                   end: CGPoint(x: 800, y: 640),
                                   style: SnipAnnotationStyle()))
                overlays.first?.overlayView.debugAddAnnotation(
                    SnipAnnotation(kind: .freehand,
                                   start: CGPoint(x: 360, y: 600),
                                   end: CGPoint(x: 760, y: 660),
                                   points: (0...20).map { index in
                                       CGPoint(x: 360 + Double(index) * 20,
                                               y: 600 + sin(Double(index) / 3.0) * 18)
                                   },
                                   style: SnipAnnotationStyle(color: .yellow, lineWidth: 5)))
                try? await Task.sleep(nanoseconds: 900_000_000)
                let verify = try await captureService.captureAllDisplays()
                guard let image = verify.first?.image else { exit(3) }
                try SnipDemo.saveImage(image, to: "/tmp/nm-snip-overlay.png")
                print("demo: 已写入 /tmp/nm-snip-overlay.png")
            } catch {
                print("overlay demo error: \(error)")
                exit(4)
            }
            exit(0)
        }
    }

    /// 仅 DEBUG：NM_SNIP_WHITEBOARD_DEMO=1 时进白板并截图取证
    func runWhiteboardDemoIfRequested() {
        guard ProcessInfo.processInfo.environment["NM_SNIP_WHITEBOARD_DEMO"] != nil else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            self.beginWhiteboard()
            try? await Task.sleep(nanoseconds: 900_000_000)
            if let image = try? await self.captureService.captureAllDisplays().first?.image {
                try? SnipDemo.saveImage(image, to: "/tmp/nm-snip-whiteboard.png")
                print("demo: 已写入 /tmp/nm-snip-whiteboard.png")
            }
            exit(0)
        }
    }
}
#endif
