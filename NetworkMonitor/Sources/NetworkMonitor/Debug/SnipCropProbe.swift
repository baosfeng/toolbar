#if DEBUG
import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 选区裁剪自证（仅 DEBUG）

/// 无人值守的坐标自证：抓屏 → 取屏幕中央固定选区 → 走**生产链路**（composedImage）落盘
///
/// 触发方式：NM_SNIP_CROP_PROBE=1 /Applications/一览.app/Contents/MacOS/NetworkMonitor
/// 产物：/tmp/nm-crop-probe-full.png（整屏原图）+ /tmp/nm-crop-probe.png（所选区域）
///
/// 为什么需要它：坐标偏移类问题（「框选 A 截到 B」）肉眼看不出来，
/// 必须把「屏幕点坐标 → 像素矩形」的真实数字与裁出来的图放在一起对照。
/// 用的不是探针自己写的裁剪公式，而是复制 / 保存真正走的那一条（SnipController.composedImage）。
@MainActor
enum SnipCropProbe {

    static let envKey = "NM_SNIP_CROP_PROBE"
    private static let fullPath = "/tmp/nm-crop-probe-full.png"
    private static let cropPath = "/tmp/nm-crop-probe.png"

    static var isRequested: Bool {
        ProcessInfo.processInfo.environment[envKey] != nil
    }

    static func run(controller: SnipController) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            do {
                let capture = controller.captureService
                let displays = capture.screens()
                guard let display = displays.first else {
                    print("probe: 无可用屏幕")
                    exit(2)
                }
                print("probe: display frame=\(display.frame) pixelSize=\(display.pixelSize) scale=\(display.backingScale)")
                let captured = try await capture.captureAllDisplays()
                guard let first = captured.first else {
                    print("probe: 无捕获结果")
                    exit(3)
                }
                let imageSize = CGSize(width: first.image.width, height: first.image.height)
                print("probe: 捕获图=\(Int(imageSize.width))×\(Int(imageSize.height))")
                try? SnipDemo.saveImage(first.image, to: fullPath)
                // 屏幕中央 400 × 300 点：偏移类问题会在这里暴露成「裁到左上角」
                let rect = CGRect(x: display.frame.midX - 200,
                                  y: display.frame.midY - 150,
                                  width: 400,
                                  height: 300)
                let pixel = SelectionGeometry.pixelRect(of: rect, in: display, imageSize: imageSize)
                print("probe: 选区=\(rect)")
                print("probe: 像素矩形=\(pixel)")
                guard let composed = controller.composedImage(captured: first,
                                                              globalRect: rect,
                                                              annotations: []) else {
                    print("probe: 生产链路合成失败")
                    exit(4)
                }
                print("probe: 合成结果=\(composed.width)×\(composed.height)")
                try SnipDemo.saveImage(composed, to: cropPath)
                print("probe: 已写入 \(fullPath) 与 \(cropPath)")
            } catch {
                print("probe error: \(error)")
                exit(5)
            }
            exit(0)
        }
    }
}
#endif
