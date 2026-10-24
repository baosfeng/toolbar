import AppKit
import NetworkMonitorCore

// MARK: - 覆盖层窗口

/// 每屏一个的截图覆盖层窗口 — 无边框、置顶到 screenSaver 层级、可跨 Space
@MainActor
final class SnipOverlayWindow: NSWindow {

    private(set) var overlayView: SnipOverlayView

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(display: SnipDisplay,
         screenshot: CGImage,
         windowInfos: [SnipWindowInfo],
         lastSelection: CGRect?,
         history: [CGRect],
         primaryHeight: CGFloat,
         delegate: SnipOverlayViewDelegate) {
        let frame = SelectionGeometry.appKitRect(fromCG: display.frame, primaryHeight: primaryHeight)
        let view = SnipOverlayView(frame: NSRect(origin: .zero, size: frame.size),
                                   screenshot: screenshot,
                                   windowInfos: windowInfos,
                                   displayOrigin: display.frame.origin,
                                   lastSelection: lastSelection,
                                   history: history)
        overlayView = view
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        isReleasedWhenClosed = false
        contentView = view
        view.delegate = delegate
    }

    /// 展示并接管键盘
    func present() {
        makeKeyAndOrderFront(nil)
        makeFirstResponder(overlayView)
    }
}
