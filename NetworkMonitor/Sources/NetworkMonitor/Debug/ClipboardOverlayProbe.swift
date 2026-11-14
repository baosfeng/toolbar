#if DEBUG
import AppKit
import NetworkMonitorCore

// MARK: - 卡片全文浮层进程内自证（仅 DEBUG）

/// 悬停浮层「真的出现 / 移出真的收 / 滚轮真的被浮层吃掉」的进程内取证
///
/// 触发：`NM_CLIPBOARD_OVERLAY_PROBE=<输出目录>`
///
/// 为什么要有它：浮层（`ClipboardCardFullTextOverlay`）此前只有代码路径证据——
/// 单测覆盖不到 NSWindow 的 orderFront 与 NSScrollView 的滚动，离屏快照又抓不到子窗口。
/// 这里走与真实鼠标**同一入口**（`ClipboardCardView.mouseEntered` / `cancelHover`）：
/// 建一个真实 borderless 窗口 + 卡片流，悬停 → 等 0.45s → 读浮层真实 NSPanel 的可见性、
/// 尺寸与正文行数；移出 → 读是否收起；再悬停 → 把滚轮事件交给卡片流，读浮层内部
/// NSScrollView 的 clip 位移（证明滚轮被浮层消费而不是滚了卡片流）。
///
/// 它证明的是「进程内真实控件状态」，不等于「屏幕上用户真的看见」——后者仍需人工在旁边看一眼。
@MainActor
enum ClipboardOverlayProbe {

    /// 探针开关
    static let envKey = "NM_CLIPBOARD_OVERLAY_PROBE"

    static func runIfRequested() -> Bool {
        guard let directory = ProcessInfo.processInfo.environment[envKey], !directory.isEmpty else {
            return false
        }
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        var lines: [String] = ["# 剪贴板卡片全文浮层 · 进程内自证"]
        let window = makeHostWindow()
        let flow = ClipboardCardFlowView(frame: NSRect(x: 0, y: 0, width: 640, height: 220))
        window.contentView = flow
        flow.render(items: [longTextItem(), shortTextItem()], selectedIndex: 0)
        window.orderFrontRegardless()
        lines.append("host window visible=\(window.isVisible) cards=\(flow.cardViews.count)")

        guard let card = flow.cardViews.first else {
            lines.append("❌ 没有卡片视图")
            finish(lines, url: url, window: window)
        }

        // 1) 悬停 0.20s：还没到 0.45s 的等待时长，浮层必须还没出现
        card.mouseEntered(with: mouseEvent(window, point: NSPoint(x: 20, y: 20)))
        spin(0.20)
        lines.append("hover 0.20s  overlay.isVisible=\(overlay?.isVisible ?? false)  (期望 false)")

        // 2) 悬停 0.45s 后：浮层出现
        spin(0.35)
        let panel = overlayPanel()
        lines.append("hover 0.55s  overlay.isVisible=\(overlay?.isVisible ?? false)  (期望 true)")
        if let panel {
            let scrollView = panel.contentView?.subviews.compactMap { $0 as? NSScrollView }.first
            let docHeight = scrollView?.documentView?.frame.height ?? 0
            let clipHeight = scrollView?.contentView.bounds.height ?? 0
            let scroller = scrollView?.hasVerticalScroller ?? false
            lines.append("overlay panel level=\(panel.level.rawValue)"
                         + " frame=\(fmt(panel.frame))"
                         + " ignoresMouseEvents=\(panel.ignoresMouseEvents)"
                         + " docHeight=\(Int(docHeight)) clipHeight=\(Int(clipHeight))"
                         + " verticalScroller=\(scroller)")
            lines.append("overlay 正文可滚=\(docHeight > clipHeight + 1)  (期望 true，超长文本)")
            if let windowShot = renderWindow(panel), let path = write(windowShot, "overlay-visible.png", url) {
                lines.append("overlay 截图=\(path)")
            }
        } else {
            lines.append("❌ 找不到浮层 NSPanel（NSApp.windows 里没有 statusBar+1 层的面板）")
            lines.append("窗口清单：\(windowInventory())")
        }

        // 3) 移出卡片：浮层必须收起
        card.cancelHover()
        spin(0.1)
        lines.append("mouseExited    overlay.isVisible=\(overlay?.isVisible ?? false)  (期望 false)")

        // 4) 再悬停 + 滚轮：滚轮必须由浮层消费（内部 clip 位移），而不是滚卡片流
        card.mouseEntered(with: mouseEvent(window, point: NSPoint(x: 20, y: 20)))
        spin(0.55)
        let before = overlayClipOriginY()
        forwardWheel(to: flow, deltaY: -40)
        let after = overlayClipOriginY()
        lines.append("wheel deltaY=-40  overlay clipY \(fmt(before)) -> \(fmt(after))"
                     + "  (clipY 变化 = 滚轮被浮层消费，没有落到卡片流)")

        finish(lines, url: url, window: window)
    }

    // MARK: 夹具

    private static func makeHostWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 240, y: 240, width: 640, height: 220),
                              styleMask: [.borderless],
                              backing: .buffered,
                              defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .statusBar
        window.animationBehavior = .none
        return window
    }

    /// 超长正文：远超浮层 9 行上限，用于验证内部滚动
    private static func longTextItem() -> ClipboardItem {
        let body = (1...40).map { "第 \($0) 行：这是一段刻意写长的剪贴板正文，用于验证悬停浮层的 9 行封顶与内部滚动。" }
            .joined(separator: "\n")
        return ClipboardItem(kind: .text,
                             text: body,
                             preview: String(body.prefix(60)),
                             contentHash: "overlay-probe-long",
                             sourceBundleID: "com.apple.Terminal",
                             sourceAppName: "终端",
                             createdAt: Date().addingTimeInterval(-300))
    }

    private static func shortTextItem() -> ClipboardItem {
        ClipboardItem(kind: .text,
                      text: "短正文",
                      preview: "短正文",
                      contentHash: "overlay-probe-short",
                      sourceBundleID: "com.apple.Notes",
                      sourceAppName: "备忘录",
                      createdAt: Date().addingTimeInterval(-120))
    }

    // MARK: 事件与状态读取

    private static func mouseEvent(_ window: NSWindow, point: NSPoint) -> NSEvent {
        NSEvent.mouseEvent(with: .mouseMoved,
                           location: point,
                           modifierFlags: [],
                           timestamp: ProcessInfo.processInfo.systemUptime,
                           windowNumber: window.windowNumber,
                           context: nil,
                           eventNumber: 0,
                           clickCount: 0,
                           pressure: 0)
            ?? NSEvent()
    }

    private static var overlay: ClipboardCardFullTextOverlay? { ClipboardCardFullTextOverlay.shared }

    /// 浮层是独立 NSPanel：认「状态栏级 + 可见 + 宽度恰为浮层固定宽 280」
    ///
    /// 不按 level 精确匹配：addChildWindow(ordered: .above) 之后系统会把子窗口层级
    /// 归到父窗口那一级显示（实测 statusBar+1 变成 statusBar），按固定宽认更稳。
    private static func overlayPanel() -> NSPanel? {
        NSApp.windows.compactMap { $0 as? NSPanel }.first {
            $0.isVisible
                && $0.level.rawValue >= NSWindow.Level.statusBar.rawValue
                && abs($0.frame.width - ClipboardCardFullTextOverlay.width) < 1
        }
    }

    /// 诊断：把当前进程的窗口清单打出来（找不到浮层时定位用）
    private static func windowInventory() -> String {
        NSApp.windows.map {
            let type = String(describing: type(of: $0))
            return "\(type) level=\($0.level.rawValue) visible=\($0.isVisible)"
                + " title=\"\($0.title)\" frame=\(fmt($0.frame))"
        }.joined(separator: " | ")
    }

    private static func overlayClipOriginY() -> CGFloat {
        guard let panel = overlayPanel(),
              let scrollView = panel.contentView?.subviews.compactMap({ $0 as? NSScrollView }).first else {
            return 0
        }
        return scrollView.contentView.bounds.origin.y
    }

    /// 把滚轮事件交给卡片流（与真实滚轮同一分发入口）
    ///
    /// NSEvent 的 scrollingDeltaY 只读，滚轮事件只能从 CGEvent 造
    private static func forwardWheel(to flow: ClipboardCardFlowView, deltaY: CGFloat) {
        guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                               wheel1: Int32(deltaY), wheel2: 0, wheel3: 0),
              let wheel = NSEvent(cgEvent: cg) else {
            FileHandle.standardError.write(Data("❌ 无法构造滚轮事件\n".utf8))
            return
        }
        flow.scrollWheel(with: wheel)
    }

    // MARK: 输出

    private static func finish(_ lines: [String], url: URL, window: NSWindow) -> Never {
        let text = lines.joined(separator: "\n") + "\n"
        try? text.write(to: url.appendingPathComponent("clipboard-overlay-probe.txt"),
                        atomically: true, encoding: .utf8)
        FileHandle.standardError.write(Data(text.utf8))
        window.orderOut(nil)
        ClipboardCardFullTextOverlay.shared.hide()
        exit(0)
    }

    private static func spin(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private static func fmt(_ value: CGFloat) -> String { String(format: "%.1f", value) }

    private static func fmt(_ rect: NSRect) -> String {
        String(format: "x=%.0f y=%.0f w=%.0f h=%.0f", rect.origin.x, rect.origin.y, rect.width, rect.height)
    }

    private static func renderWindow(_ window: NSWindow) -> Data? {
        guard let view = window.contentView else { return nil }
        let size = view.bounds.size
        guard size.width > 1, size.height > 1,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: Int(size.width * 2),
                                         pixelsHigh: Int(size.height * 2),
                                         bitsPerSample: 8,
                                         samplesPerPixel: 4,
                                         hasAlpha: true,
                                         isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0,
                                         bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: 2, y: 2)
        view.displayIgnoringOpacity(view.bounds, in: context)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    private static func write(_ data: Data, _ name: String, _ directory: URL) -> String? {
        let file = directory.appendingPathComponent(name)
        try? data.write(to: file)
        return file.path
    }
}
#endif
