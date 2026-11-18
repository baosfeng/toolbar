#if DEBUG
import AppKit

// MARK: - 贴图拖动自证的进程内取证（CGWindowList + 抓屏）

/// 从 PinDragProbe 拆出：拖动前后的独立证据都由进程内自己采集
///
/// 为什么不借外部截图工具：外部进程（nmcli shot / screencapture）一旦被拉起就会抢前台，
/// 而贴图窗的拖动恰好对「App 是否活跃」敏感（实测非活跃时首次点击会被吞掉），
/// 取证手段本身会改变被取证的行为。因此这里用 CGWindowList 与 CGDisplayCreateImage，
/// 全程留在本进程内，不改变焦点。
@MainActor
extension PinDragProbe {

    static let beforePath = "/tmp/pin-drag-before.png"
    static let afterPath = "/tmp/pin-drag-after.png"

    /// 贴图窗（layer=1000）在 CGWindowList 里的屏幕 bounds —— 与 AppKit frame 互为独立证据
    static func screenBoundsDescription() -> String {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else {
            return "取不到窗口列表"
        }
        var parts: [String] = []
        for info in list {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 1000,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let x = bounds["X"] as? Double, let y = bounds["Y"] as? Double,
                  let width = bounds["Width"] as? Double, let height = bounds["Height"] as? Double else { continue }
            parts.append("(\(Int(x)), \(Int(y))) \(Int(width))×\(Int(height))")
        }
        return parts.isEmpty ? "无 layer=1000 窗口" : parts.joined(separator: " | ")
    }

    /// 抓一张整屏 PNG（只用于自证，失败不影响结论）
    static func captureScreen(to path: String) {
        guard let display = CGMainDisplayID() as CGDirectDisplayID?,
              let image = CGDisplayCreateImage(display) else {
            print("🔎 抓屏失败：取不到显示图像（可能缺屏幕录制授权）")
            return
        }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
        print("🔎 已抓屏：\(path)")
    }


}
#endif
