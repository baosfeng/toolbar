#if DEBUG
import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 截图工具条离屏取证（仅 DEBUG）

/// 把工具条离屏渲染成 PNG，供人核对四组按钮的左右留白、分隔线、文字提示三档
///
/// 触发方式：`NM_SNIP_TOOLBAR_SNAPSHOT_DIR=/tmp/nm-snip-toolbar <可执行>`
/// 产物：
/// - `toolbar-hover-tool.png`：悬停档，悬停在「箭头」上（气泡 + 提亮）
/// - `toolbar-hover-color.png`：悬停档，悬停在颜色圆点
/// - `toolbar-labels.png`：常驻标签档（条高 50pt，图标下带中文名）
/// - `toolbar-icononly.png`：仅图标档（老外观）
/// - `toolbar-custom.png`：隐藏颜色 / 线宽组、常驻工具换成三个的自定义排列
/// - `panel-*.png`：二级面板（工具 / 颜色 / 线宽）
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

            renderBar(.standard, hover: .tool(.arrow),
                      to: directory.appendingPathComponent("toolbar-hover-tool.png"))
            renderBar(.standard, hover: .color,
                      to: directory.appendingPathComponent("toolbar-hover-color.png"))
            renderBar(SnipToolBarConfiguration(labelMode: .always), hover: nil,
                      to: directory.appendingPathComponent("toolbar-labels.png"))
            renderBar(SnipToolBarConfiguration(labelMode: .iconOnly), hover: nil,
                      to: directory.appendingPathComponent("toolbar-icononly.png"))
            // 自定义排列：只留工具与输出动作，常驻工具换成矩形 / 文字 / 橡皮擦
            renderBar(SnipToolBarConfiguration(visibleGroups: [.tools, .actions],
                                              primaryTools: [.rectangle, .text, .eraser]),
                      hover: .more,
                      to: directory.appendingPathComponent("toolbar-custom.png"))

            renderPanel(.tools(SnipTool.overflow), hoverIndex: 0,
                        to: directory.appendingPathComponent("panel-tools.png"))
            renderPanel(.colors(SnipToolBarView.colors), hoverIndex: 1,
                        to: directory.appendingPathComponent("panel-colors.png"))
            renderPanel(.styles(widths: SnipToolBarView.widths,
                                dashes: SnipToolBarView.dashes,
                                alphas: SnipToolBarView.alphas),
                        hoverIndex: 1,
                        to: directory.appendingPathComponent("panel-styles.png"))
            renderPanel(.tools(SnipTool.overflow), labelMode: .always,
                        to: directory.appendingPathComponent("panel-tools-labels.png"))
            NSApp.terminate(nil)
        }
    }

    /// 渲染一张工具条：给定配置与悬停项
    private static func renderBar(_ configuration: SnipToolBarConfiguration,
                                  hover: SnipBarItem?,
                                  to url: URL) {
        let bar = SnipToolBarView(configuration: configuration)
        bar.selectedTool = .arrow
        var style = SnipAnnotationStyle()
        style.color = .red
        style.lineWidth = 4
        bar.debugSetStyle(style)
        if let hover { bar.debugHover(hover) }

        let size = SnipToolBarView.frameSize(for: configuration).size
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

        writePNG(of: container, size: size, to: url)
    }

    /// 渲染一张二级面板（带一个悬停项，取证文字气泡）
    private static func renderPanel(_ content: SnipPanelContent,
                                    labelMode: SnipToolBarLabelMode = .hover,
                                    hoverIndex: Int? = nil,
                                    to url: URL) {
        let panel = SnipToolPanelView(content: content, selectedIndex: nil, labelMode: labelMode)
        if let hoverIndex { panel.debugHover(index: hoverIndex) }
        guard let appearance = NSAppearance(named: .darkAqua) else { return }
        let size = content.size(labelMode: labelMode)
        let container = SnapshotBackdropView(frame: NSRect(origin: .zero, size: size))
        container.appearance = appearance
        panel.appearance = appearance
        panel.frame = NSRect(origin: .zero, size: size)
        container.addSubview(panel)
        container.layoutSubtreeIfNeeded()
        panel.needsDisplay = true
        panel.displayIfNeeded()
        container.needsDisplay = true
        container.displayIfNeeded()
        writePNG(of: container, size: size, to: url)
        AppContext.shared.logger.info("面板取证已写入 \(url.lastPathComponent) \(Int(size.width))x\(Int(size.height))")
    }

    /// 把视图快照成 PNG（工具条与面板共用）
    private static func writePNG(of view: NSView, size: NSSize, to url: URL) {
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
            AppContext.shared.logger.error("快照位图创建失败")
            return
        }
        rep.size = size
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        do {
            try data.write(to: url)
            AppContext.shared.logger.info("取证已写入 \(url.lastPathComponent) \(pixelWidth)x\(pixelHeight)")
        } catch {
            AppContext.shared.logger.error("快照写入失败：\(error)")
        }
    }
}
#endif
