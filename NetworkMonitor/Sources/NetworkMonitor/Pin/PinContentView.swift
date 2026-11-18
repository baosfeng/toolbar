import AppKit
import NetworkMonitorUI

// MARK: - 贴图窗内容视图

/// 贴图窗的内容视图：把「左键双击关闭」「中键单击重置」「按住拖动移动窗口」「右键菜单」分开
///
/// 官方贴图行为是「左键双击关闭」「中键单击重置为 100% 大小与 100% 不透明」，
/// 同时贴图要能被鼠标拖到屏幕任意位置。拖动为什么不能靠窗口默认行为，实测结论有三条
/// （证据见 .handoff-pin-move.md）：
/// 1. `super.mouseDown` 在 `.nonactivatingPanel` 上不启动拖动会话，窗口 frame 一格没动；
/// 2. `NSWindow.performDrag(with:)` 依赖 Window Server 的拖动会话，**App 非活跃时静默失效**；
/// 3. 非活跃时第一次点击根本不投递给视图（`mouseDown` 不被调用）——
///    因为 `.nonactivatingPanel` 的这次点击默认只用于「让窗口成为 key」。
/// 因此这里做三件事：acceptsFirstMouse 让首次点击直达视图；
/// 拖动不再借 Window Server，而是按下记起点、拖动按鼠标位移平移窗口（PinDragSession）。
@MainActor
final class PinContentView: NSView {

    /// 关闭当前贴图（可恢复）
    var onCloseRequest: (() -> Void)?
    /// 重置为 100% 大小与 100% 不透明
    var onResetRequest: (() -> Void)?

    /// 当前拖动会话（nil = 没在拖）
    private var dragSession: PinDragSession?

    override var isOpaque: Bool { false }

    /// 非活跃时也要把第一次点击投递给本视图
    ///
    /// 贴图窗是 `.nonactivatingPanel` 且 App 是 `.accessory`：切到别的 App 后再回来点贴图，
    /// 这次点击默认只用来让窗口成为 key window，事件不会投递给视图——
    /// 实测 `mouseDown` 完全不被调用、窗口也一动不动（这就是「贴图不支持移动」的体感来源）。
    /// 返回 true 后，第一次点击就直接进内容视图，拖动立刻可用。
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// 命中测试一律落回本视图
    ///
    /// 内容视图里压着 imageView，命中测试会先落在它身上；而「非活跃时第一次点击是否投递」
    /// 是按**被命中的那个视图**的 acceptsFirstMouse 判的 —— 子视图没有实现就默认 false，
    /// 于是首次点击照样被吞（实测 mouseDown 次数 0、窗口不动）。
    /// 把命中测试收敛到本视图后，鼠标语义只有这一处入口，拖动 / 双击 / 中键都在这里判。
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return bounds.contains(local) ? self : nil
    }

    // MARK: - 按下

    override func mouseDown(with event: NSEvent) {
#if DEBUG
        PinDragProbe.recordMouseDown()
#endif
        switch PinClickIntent.outcome(buttonNumber: event.buttonNumber, clickCount: event.clickCount) {
        case .closeWindow:
            onCloseRequest?()
        case .dragWindow:
            beginDrag()
        case .resetSizeAndAlpha, .passThrough:
            super.mouseDown(with: event)
        }
    }

    override func otherMouseDown(with event: NSEvent) {
        switch PinClickIntent.outcome(buttonNumber: event.buttonNumber, clickCount: event.clickCount) {
        case .resetSizeAndAlpha:
            onResetRequest?()
        case .closeWindow, .dragWindow, .passThrough:
            super.otherMouseDown(with: event)
        }
    }

    // MARK: - 拖动

    /// 记下起始位置，真正的位移在 mouseDragged 里算
    private func beginDrag() {
        guard let window else { return }
        dragSession = PinDragSession(startOrigin: window.frame.origin,
                                     startMouse: NSEvent.mouseLocation)
#if DEBUG
        PinDragProbe.noteDragStart(origin: window.frame.origin, mouse: NSEvent.mouseLocation)
#endif
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let session = dragSession else {
            super.mouseDragged(with: event)
            return
        }
        let mouse = NSEvent.mouseLocation
        // 未越过拖动阈值时当作单击：手一抖不该把贴图挪走半像素
        guard session.isDragBeyondThreshold(mouse: mouse) else { return }
        window.setFrameOrigin(session.origin(forMouse: mouse))
#if DEBUG
        PinDragProbe.recordDragFrame(window.frame)
#endif
    }

    override func mouseUp(with event: NSEvent) {
        dragSession = nil
        super.mouseUp(with: event)
    }
}
