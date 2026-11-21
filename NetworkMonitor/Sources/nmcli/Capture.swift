import CoreGraphics
import Foundation
import ImageIO

// MARK: - 截图

enum Capture {

    /// 截图来源：窗口 id / 屏幕矩形 / 全屏三选一
    enum Source: Equatable {
        case window(Int)
        case rect(CGRect)
        case screen
    }

    /// 拿到像素的方式（回退链的最终形态，写进输出与 summary 便于事后分辨）
    enum Mode: String {
        case window
        /// `-l<id>` 失败后按 CGWindowList 现查 bounds 走的矩形截图
        case rectFallback
        case rect
        case screen
    }

    /// 调系统 `screencapture` 落盘，返回文件大小与像素尺寸
    ///
    /// 为什么用 screencapture 而不是 CGWindowListCreateImage：后者在 macOS 15+ 已废弃，
    /// 且对非激活面板会拿到空图；screencapture 走系统同一条取帧路径。
    ///
    /// **窗口截图有回退**：`screencapture -l<id>` 对 layer=25 的菜单面板会报
    /// `could not create image from window`（实测，exit 1）。这时按窗口 id 现查
    /// CGWindowList 的 bounds 走 `-R` 矩形截图，并把 mode 标成 `rectFallback`——
    /// 不静默：矩形口径会多截到面板阴影外的背景，读图的人必须知道这一点。
    @discardableResult
    static func shot(_ source: Source, to path: String) throws -> ShotResult {
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true)
        switch source {
        case .window(let id):
            if let result = try? capture(.window(id), mode: .window, to: path) {
                return result
            }
            guard let bounds = WindowList.all().first(where: { $0.id == id })?.bounds, bounds.width >= 2 else {
                throw CLIError("窗口截图失败且查不到 bounds：window id=\(id)")
            }
            return try capture(.rect(bounds), mode: .rectFallback, to: path)
        case .rect, .screen:
            return try capture(source, mode: source == .screen ? .screen : .rect, to: path)
        }
    }

    private static func capture(_ source: Source, mode: Mode, to path: String) throws -> ShotResult {
        var arguments = ["-x"]
        switch source {
        case .window(let id):
            arguments.append("-l\(id)")
        case .rect(let rect):
            arguments.append("-R\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height))")
        case .screen:
            break
        }
        arguments.append(path)
        // screencapture 对失败也会留下空 / 残缺文件，先删掉避免读到大图或旧图
        try? FileManager.default.removeItem(atPath: path)
        let status = run("/usr/sbin/screencapture", arguments)
        guard status == 0, let size = pixelSize(of: path) else {
            throw CLIError("screencapture 失败（exit \(status)）：\(arguments.joined(separator: " "))")
        }
        let bytes = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
        return ShotResult(path: path, width: size.width, height: size.height, bytes: bytes, mode: mode)
    }

    private static func run(_ launchPath: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        do {
            try process.run()
        } catch {
            return -1
        }
        process.waitUntilExit()
        return process.terminationStatus
    }

    static func pixelSize(of path: String) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (width, height)
    }
}

struct ShotResult {
    let path: String
    let width: Int
    let height: Int
    let bytes: Int
    let mode: Capture.Mode

    var describe: String {
        let suffix = mode == .rectFallback ? " (via rect fallback)" : ""
        return "\(path) \(width)x\(height) \(bytes)B [\(mode.rawValue)]\(suffix)"
    }
}
