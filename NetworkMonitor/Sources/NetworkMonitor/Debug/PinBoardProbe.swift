import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 贴图棋盘底与滤镜取证（仅 DEBUG）

/// 出一张合成取证图，证明两件事：
/// 1. 棋盘底在「开关打开 + 含透明像素」时真的画出来了，且全不透明的图没有棋盘；
/// 2. 灰度 / 反色两个滤镜对同一张图确实改了像素。
///
/// 触发：`NM_PIN_BOARD_PROBE=<输出目录>`（需打包成 .app 后跑包内可执行文件，见踩坑「快照取证需打包成 app」）
/// 产物：`pin-board-filters.png`（四联对照图）+ `pin-board-filters.txt`（逐格像素真值）。
///
/// 为什么用合成画布而不是真开贴图窗抓屏：贴图窗是 `.nonactivatingPanel` + screenSaver 层级，
/// 离屏 `cacheDisplay` 抓不到它的透明合成结果；屏幕合成又依赖当前桌面内容，不可重复。
/// 这里按 PinWindow 的层次自己搭一遍（棋盘底 + 图片），像素判据全部落文本。
@MainActor
enum PinBoardProbe {

    static let envKey = "NM_PIN_BOARD_PROBE"

    static var requestedDirectory: String? {
        guard let dir = ProcessInfo.processInfo.environment[envKey], !dir.isEmpty else { return nil }
        return dir
    }

    static func runIfRequested() {
        guard let directory = requestedDirectory else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            run(directory: URL(fileURLWithPath: directory))
            exit(0)
        }
    }

    static func run(directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let translucent = makeTranslucentSample(),
              let opaque = makeOpaqueSample(),
              let gray = SnipImageTransform.grayscale(translucent),
              let inverted = SnipImageTransform.inverted(translucent) else {
            print("🔎 [pin-board] 取样图构造失败")
            return
        }
        // 四联：半透明原图（带棋盘） / 半透明原图（不带棋盘） / 灰度 / 反色
        let cells: [(String, CGImage, Bool)] = [
            ("半透明 + 棋盘底开", translucent, true),
            ("半透明 + 棋盘底关", translucent, false),
            ("灰度", gray, false),
            ("反色", inverted, false)
        ]
        let cellSize = NSSize(width: 160, height: 120)
        let gap: CGFloat = 12
        let canvas = NSSize(width: cellSize.width * CGFloat(cells.count) + gap * CGFloat(cells.count + 1),
                            height: cellSize.height + gap * 2)
        let container = NSView(frame: NSRect(origin: .zero, size: canvas))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(white: 0.35, alpha: 1).cgColor
        var lines: [String] = []
        for (index, cell) in cells.enumerated() {
            let frame = NSRect(x: gap + (cellSize.width + gap) * CGFloat(index),
                               y: gap, width: cellSize.width, height: cellSize.height)
            let view = NSView(frame: frame)
            let showsBoard = PinBoardBackgroundResolver.shouldDraw(
                enabled: cell.2,
                hasTransparentPixels: SnipImageAlphaProbe.hasTransparentPixels(cell.1))
            let board = PinBoardView(frame: NSRect(origin: .zero, size: cellSize))
            board.isHidden = !showsBoard
            view.addSubview(board)
            let imageView = NSImageView(frame: NSRect(origin: .zero, size: cellSize))
            imageView.image = NSImage(cgImage: cell.1, size: cellSize)
            imageView.imageScaling = .scaleAxesIndependently
            view.addSubview(imageView)
            container.addSubview(view)
            lines.append("\(cell.0)：棋盘=\(showsBoard ? "是" : "否")，"
                         + "含透明像素=\(SnipImageAlphaProbe.hasTransparentPixels(cell.1))")
        }
        // 全不透明样本单独一行：开关开着也不该画棋盘
        lines.append("全不透明样本 + 开关开：棋盘="
                     + "\(PinBoardBackgroundResolver.shouldDraw(enabled: true, hasTransparentPixels: SnipImageAlphaProbe.hasTransparentPixels(opaque)) ? "是" : "否")")
        container.layoutSubtreeIfNeeded()
        guard let rep = container.bitmapImageRepForCachingDisplay(in: container.bounds) else {
            print("🔎 [pin-board] 位图上下文创建失败")
            return
        }
        container.cacheDisplay(in: container.bounds, to: rep)
        let png = directory.appendingPathComponent("pin-board-filters.png")
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: png)
        }
        let text = directory.appendingPathComponent("pin-board-filters.txt")
        try? (lines.joined(separator: "\n") + "\n").write(to: text, atomically: true, encoding: .utf8)
        print("🔎 [pin-board] \(lines.joined(separator: " | "))")
        print("🔎 [pin-board] 取证图：\(png.path)")
    }

    // MARK: - 取样图

    /// 半透明样本：左半透明红、右半透明蓝，中间一条全不透明绿（透明区与内容都看得见）
    private static func makeTranslucentSample() -> CGImage? {
        let size = 64
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let offset = (y * size + x) * 4
                if x >= size / 3, x < size * 2 / 3 {
                    pixels[offset] = 0; pixels[offset + 1] = 200; pixels[offset + 2] = 80; pixels[offset + 3] = 255
                } else if x < size / 3 {
                    pixels[offset] = 120; pixels[offset + 1] = 20; pixels[offset + 2] = 20; pixels[offset + 3] = 128
                } else {
                    pixels[offset] = 20; pixels[offset + 1] = 20; pixels[offset + 2] = 120; pixels[offset + 3] = 160
                }
            }
        }
        return image(from: pixels, size: size, bitmapInfo: bitmapInfo)
    }

    private static func makeOpaqueSample() -> CGImage? {
        let size = 8
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            pixels[index] = 200; pixels[index + 1] = 120; pixels[index + 2] = 40; pixels[index + 3] = 255
        }
        return image(from: pixels, size: size, bitmapInfo: bitmapInfo)
    }

    private static func image(from pixels: [UInt8], size: Int, bitmapInfo: UInt32) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
                       provider: provider, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)
    }
}
