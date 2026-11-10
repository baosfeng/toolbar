#if DEBUG
import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 截图工具条离屏取证（仅 DEBUG）

/// 把工具条离屏渲染成 PNG，供人核对四组按钮的左右留白与分隔线位置
///
/// 触发方式：`NM_SNIP_TOOLBAR_SNAPSHOT_DIR=/tmp/nm-snip-toolbar <可执行>`
/// 产物：`toolbar-dark.png`（1pt = 1px，尺寸即工具条真实宽度）
///
/// 为什么不让真机屏幕截图来核对：覆盖层跑在 screenSaver 层级、锁屏/息屏时拍不到，
/// 而离屏渲染与真实窗口走同一套 `draw`，排版结果等价。
@MainActor
enum SnipToolBarSnapshot {

    static let directoryEnvKey = "NM_SNIP_TOOLBAR_SNAPSHOT_DIR"

    static var isRequested: Bool {
        ProcessInfo.processInfo.environment[directoryEnvKey]?.isEmpty == false
    }

    static func runIfRequested() {
        guard let path = ProcessInfo.processInfo.environment[directoryEnvKey], !path.isEmpty else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            let directory = URL(fileURLWithPath: path, isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            render(to: directory.appendingPathComponent("toolbar-dark.png"))
            NSApp.terminate(nil)
        }
    }

    /// 渲染一张「选中工具 + 选中颜色 + 选中线宽」的工具条
    private static func render(to url: URL) {
        let bar = SnipToolBarView()
        bar.selectedTool = .arrow
        var style = SnipAnnotationStyle()
        style.color = .red
        style.lineWidth = 4
        bar.debugSetStyle(style)

        let size = NSSize(width: SnipToolBarLayout.plan(toolCount: SnipTool.allCases.count,
                                                        colorCount: 7, widthCount: 3,
                                                        actionCount: SnipBarAction.allCases.count).width,
                          height: SnipToolBarLayout.height)
        guard let appearance = NSAppearance(named: .darkAqua) else { return }
        let container = SnapshotBackdropView(frame: NSRect(origin: .zero, size: size))
        container.appearance = appearance
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = container
        window.appearance = appearance
        bar.appearance = appearance
        bar.frame = NSRect(origin: .zero, size: size)
        container.addSubview(bar)

        container.layoutSubtreeIfNeeded()
        bar.needsDisplay = true
        container.needsDisplay = true
        bar.displayIfNeeded()
        container.displayIfNeeded()

        let pixelWidth = max(1, Int(size.width.rounded()))
        let pixelHeight = max(1, Int(size.height.rounded()))
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
            AppContext.shared.logger.error("工具条取证位图创建失败")
            return
        }
        rep.size = size
        container.cacheDisplay(in: container.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        do {
            try data.write(to: url)
            AppContext.shared.logger.info("工具条取证已写入 \(url.lastPathComponent) \(pixelWidth)x\(pixelHeight)")
        } catch {
            AppContext.shared.logger.error("工具条取证写入失败：\(error)")
        }
    }
}
#endif
