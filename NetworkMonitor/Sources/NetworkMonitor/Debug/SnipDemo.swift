#if DEBUG
import AppKit
import NetworkMonitorCore

// MARK: - 截图 / 贴图自证钩子（仅 DEBUG）

/// 无人工介入的冒烟取证：截主屏 → 裁一块贴到屏幕 → 再截整屏存 PNG → 退出
///
/// 触发方式：NM_SNIP_DEMO=1 .build/arm64-apple-macosx/debug/NetworkMonitor
/// 产物：/tmp/nm-snip-demo.png（第二次截图，应能看到贴图窗叠在桌面上）
@MainActor
enum SnipDemo {

    static let envKey = "NM_SNIP_DEMO"
    static let outputPath = "/tmp/nm-snip-demo.png"

    static var isRequested: Bool {
        ProcessInfo.processInfo.environment[envKey] != nil
    }

    static func run(capture: any SnipCaptureServicing,
                    pin: PinWindowController,
                    openSettings: (() -> Void)? = nil) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            do {
                let captures = try await capture.captureAllDisplays()
                guard let main = captures.first else {
                    print("demo: 没有可用屏幕")
                    exit(2)
                }
                // 第一张：原样
                let first = pin.pin(captured: main, cgRect: CGRect(x: 120, y: 180, width: 420, height: 280))
                first?.setScale(0.85)
                // 第二张：旋转 90° + 半透明
                let second = pin.pin(captured: main, cgRect: CGRect(x: 700, y: 200, width: 420, height: 280))
                second?.rotate(clockwise: true)
                second?.adjustAlpha(by: -0.4)
                // 第三张：缩略图
                let third = pin.pin(captured: main, cgRect: CGRect(x: 300, y: 620, width: 420, height: 280))
                third?.toggleThumbnail()
                // 设置窗：打开后截一张，供界面取证
                openSettings?()
                try? await Task.sleep(nanoseconds: 600_000_000)
                if let settingsImage = try await capture.captureAllDisplays().first?.image {
                    try SnipDemo.saveImage(settingsImage, to: "/tmp/nm-snip-settings.png")
                    print("demo: 已写入 /tmp/nm-snip-settings.png")
                }
                // 第四张：剪贴板文本转贴图
                if let rendered = SnipClipboardRenderer.render(.text("这是一个从剪贴板文本生成的贴图。\n第二行内容，用于验证自动换行与留白。\n第三行。")) {
                    pin.pin(image: rendered.image,
                            cgRect: CGRect(x: 1150, y: 620,
                                           width: rendered.size.width,
                                           height: rendered.size.height))
                }
                // 第五张：颜色卡片
                if let color = SnipClipboardRenderer.render(.color(SnipPixelColor(red: 64, green: 156, blue: 255))) {
                    pin.pin(image: color.image,
                            cgRect: CGRect(x: 1150, y: 420,
                                           width: color.size.width,
                                           height: color.size.height))
                }
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                let verify = try await capture.captureAllDisplays()
                guard let image = verify.first?.image else {
                    print("demo: 第二次截图失败")
                    exit(3)
                }
                try saveImage(image, to: outputPath)
                print("demo: 已写入 \(outputPath)")
            } catch {
                print("demo error: \(error)")
                exit(4)
            }
            exit(0)
        }
    }

    static func saveImage(_ image: CGImage, to path: String) throws {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw SnipCaptureError.captureFailed("PNG 编码失败")
        }
        try data.write(to: URL(fileURLWithPath: path))
    }
}
#endif
