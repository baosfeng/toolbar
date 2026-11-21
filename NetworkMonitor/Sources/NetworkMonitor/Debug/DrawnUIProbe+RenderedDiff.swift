#if DEBUG
import AppKit
import NetworkMonitorCore
import NetworkMonitorDesign
import NetworkMonitorUI

// MARK: - 2 倍渲染对照（1x 离屏快照会把原生标签的 alpha 文字合成两次）

extension DrawnUIProbe {

    /// 以 2 倍位图渲染系统页面板 —— 用来判定「1x 快照里原生标签偏深」是不是渲染路径问题
    ///
    /// 触发：NM_DRAWN_COUNT_2X=<png 路径>
    /// 用法：同一页同时出 1x 图与 2x 图，量同一处原生标签的墨色深浅；
    /// 若 2x 下墨色等于「单次 alpha 合成」而 1x 下等于「两次合成」，说明偏深只发生在 1x 位图。
    /// internal：入口 runIfRequested 在 DrawnUIProbe.swift，跨文件调用需放宽访问级别
    static func runTwoTimesRenderIfRequested() -> Bool {
        guard let path = ProcessInfo.processInfo.environment["NM_DRAWN_COUNT_2X"],
              !path.isEmpty else { return false }
        let panel = MenuPanelSnapshot.makeMenuPanel(tab: .system, items: [])
        let height = min(max(panel.desiredContentHeight, 180), MenuPanelStyle.maxHeight)
        let size = NSSize(width: MenuPanelStyle.panelWidth, height: height.rounded(.up))
        let scale: CGFloat = 2
        guard let appearance = NSAppearance(named: .aqua) else { exit(1) }
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.appearance = appearance
        container.wantsLayer = true
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = container
        panel.appearance = appearance
        panel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(panel)
        NSLayoutConstraint.activate([
            panel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            panel.topAnchor.constraint(equalTo: container.topAnchor),
            panel.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        container.layoutSubtreeIfNeeded()
        panel.needsDisplay = true
        container.displayIfNeeded()
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: Int(size.width * scale),
                                         pixelsHigh: Int(size.height * scale),
                                         bitsPerSample: 8,
                                         samplesPerPixel: 4,
                                         hasAlpha: true,
                                         isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0,
                                         bitsPerPixel: 0) else { exit(1) }
        rep.size = size
        // 两种取图方式各出一张：cacheDisplay 会走图层合成，displayIgnoringOpacity 直接调 draw
        container.cacheDisplay(in: container.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
        if let directRep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                            pixelsWide: Int(size.width * scale),
                                            pixelsHigh: Int(size.height * scale),
                                            bitsPerSample: 8,
                                            samplesPerPixel: 4,
                                            hasAlpha: true,
                                            isPlanar: false,
                                            colorSpaceName: .deviceRGB,
                                            bytesPerRow: 0,
                                            bitsPerPixel: 0),
           let directContext = NSGraphicsContext(bitmapImageRep: directRep) {
            directRep.size = size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = directContext
            directContext.cgContext.scaleBy(x: scale, y: scale)
            panel.displayIgnoringOpacity(panel.bounds, in: directContext)
            NSGraphicsContext.restoreGraphicsState()
            if let data = directRep.representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: path + ".direct.png"))
            }
        }
        exit(0)
    }
}
#endif
