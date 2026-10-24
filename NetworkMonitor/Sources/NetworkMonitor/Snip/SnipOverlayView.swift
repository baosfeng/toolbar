import AppKit
import NetworkMonitorCore

// MARK: - 覆盖层回调

@MainActor
protocol SnipOverlayViewDelegate: AnyObject {
    /// 用户按 Esc 或右键取消
    func overlayViewDidCancel(_ view: SnipOverlayView)
    /// 用户回车确认（本地点坐标）
    func overlayView(_ view: SnipOverlayView, didConfirm rect: CGRect)
    /// 用户要求切换「截图里是否包含鼠标指针」
    func overlayViewDidToggleCursor(_ view: SnipOverlayView)
    /// 用户要求保存选区（本地点坐标）；quick 为 true 表示快速保存
    func overlayView(_ view: SnipOverlayView, didRequestSave rect: CGRect, quick: Bool)
    /// 用户要求把选区贴到屏幕（本地点坐标）
    func overlayView(_ view: SnipOverlayView, didRequestPin rect: CGRect)
}

// MARK: - 截图覆盖层

/// 单屏截图覆盖层 — 画截图、暗化、选区、手柄，并处理鼠标与键盘
///
/// 坐标约定：视图 isFlipped，本地坐标与全局 CG 坐标只差 display.frame.origin 偏移。
/// 尺寸输入框 — 回车提交，Esc 取消（覆盖 cancelOperation 才能拦到 Esc）
@MainActor
final class SizeEditorField: NSTextField {

    var onCancel: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
            return
        }
        super.keyDown(with: event)
    }
}

@MainActor
final class SnipOverlayView: NSView {

    static let handleSize: CGFloat = 8
    static let frameLineWidth: CGFloat = 1

    weak var delegate: SnipOverlayViewDelegate?

    /// 放宽为 internal：动作扩展文件要改状态机
    var state = SnipSelectionState()
    /// 放宽为 internal：绘制扩展文件需要读取
    var screenshot: CGImage
    private let windowInfos: [SnipWindowInfo]
    let displayOrigin: CGPoint
    /// 截图像素采样器（取色与放大镜共用）
    var sampler: SnipPixelSampler?
    /// 取色展示格式，Shift 切换
    private(set) var colorFormat: SnipPixelColor.DisplayFormat = .hex
    /// 放宽为 internal：动作扩展文件要恢复上次区域
    let lastSelection: CGRect?
    /// 放宽为 internal：动作扩展文件要按逗号 / 句号循环
    let history: [CGRect]
    var historyIndex: Int?
    var pointer: CGPoint = .zero
    private var tracking: NSTrackingArea?
    var hoveredWindow: SnipWindowInfo?
    private var windowDetectionEnabled = true
    /// 尺寸标签的实际矩形（绘制时更新），点击它可输入精确尺寸
    var sizeLabelFrame: CGRect = .zero
    /// 放宽为 internal：动作扩展文件要创建与移除输入框
    var sizeEditor: SizeEditorField?
    /// 放宽为 internal：DEBUG 取证时冻结指针位置
    var debugPointerFrozen = false
    /// 当前标注工具；nil 表示仍在操作选区
    var activeTool: SnipTool?
    /// 已完成的标注
    var annotationStack = SnipAnnotationStack()
    /// 正在绘制的标注
    var draftAnnotation: SnipAnnotation?
    /// 后续图元使用的样式
    var currentStyle = SnipAnnotationStyle()
    /// 标注工具条
    var toolbarView: SnipToolBarView?
    /// 工具条是否可见（空格切换）
    var toolbarVisible = true
    /// 文字输入框
    var textEditor: SizeEditorField?
    /// 文字输入锚点（本地点坐标）
    var textEditingAnchor: CGPoint = .zero
    /// 当前选中的标注下标（文字缩放 / 旋转用）
    var selectedAnnotationIndex: Int?

    init(frame: NSRect,
         screenshot: CGImage,
         windowInfos: [SnipWindowInfo],
         displayOrigin: CGPoint,
         lastSelection: CGRect?,
         history: [CGRect]) {
        self.screenshot = screenshot
        self.windowInfos = windowInfos
        self.displayOrigin = displayOrigin
        self.lastSelection = lastSelection
        self.history = history
        super.init(frame: frame)
        wantsLayer = true
        sampler = SnipPixelSampler(image: screenshot)
        let bar = SnipToolBarView()
        bar.delegate = self
        bar.isHidden = true
        addSubview(bar)
        toolbarView = bar
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("不支持从 nib 创建")
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        tracking = area
    }

    // MARK: - 鼠标

    override func mouseMoved(with event: NSEvent) {
        #if DEBUG
        if debugPointerFrozen { return }
        #endif
        pointer = localPoint(of: event)
        if state.phase == .idle {
            updateHoveredWindow()
            needsDisplay = true
        }
    }

    /// 未起选区时按鼠标位置探测窗口，供点选
    func updateHoveredWindow() {
        guard windowDetectionEnabled else {
            hoveredWindow = nil
            return
        }
        let global = CGPoint(x: pointer.x + displayOrigin.x, y: pointer.y + displayOrigin.y)
        hoveredWindow = SnipWindowHitTesting.window(at: global, in: windowInfos)
    }

    override func mouseDown(with event: NSEvent) {
        let point = localPoint(of: event)
        pointer = point
        if event.type == .rightMouseDown {
            delegate?.overlayViewDidCancel(self)
            return
        }
        if state.phase == .selected, sizeEditor == nil, sizeLabelFrame.contains(point) {
            beginSizeEditing()
            return
        }
        if handleAnnotationMouseDown(at: point) { return }
        if let handle = state.hitTest(point, handleSize: Self.handleSize) {
            state.beginAdjust(handle, at: point)
        } else if state.phase == .idle, let hovered = hoveredWindow {
            // 点选窗口：直接成立选区，之后仍可用手柄微调
            let local = hovered.frame.offsetBy(dx: -displayOrigin.x, dy: -displayOrigin.y)
            state.select(local)
            hoveredWindow = nil
        } else {
            state.begin(at: point)
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = localPoint(of: event)
        pointer = point
        if handleAnnotationMouseDragged(to: point) { return }
        if state.phase == .dragging {
            state.drag(to: point)
        } else {
            state.adjust(to: point, lockingAspect: event.modifierFlags.contains(.shift))
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if handleAnnotationMouseUp() { return }
        if state.phase == .dragging {
            state.end()
        } else {
            state.endAdjust()
        }
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) {
        delegate?.overlayViewDidCancel(self)
    }

    /// 选中文字时滚轮改字号
    override func scrollWheel(with event: NSEvent) {
        guard let index = selectedAnnotationIndex,
              annotationStack.annotations.indices.contains(index) else {
            super.scrollWheel(with: event)
            return
        }
        var annotation = annotationStack.annotations[index]
        let next = min(max(annotation.fontScale + event.scrollingDeltaY * 0.03, 0.4), 5)
        guard abs(next - annotation.fontScale) > 0.001 else { return }
        annotation.fontScale = next
        annotationStack.replace(at: index, with: annotation)
        needsDisplay = true
    }

    // MARK: - 键盘

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53:
            if selectedAnnotationIndex != nil {
                selectedAnnotationIndex = nil
                needsDisplay = true
                return
            }
            if draftAnnotation != nil {
                draftAnnotation = nil
                needsDisplay = true
                return
            }
            delegate?.overlayViewDidCancel(self)
            return
        case 36, 76:
            if finishPolylineDraft() { return }
            confirm()
            return
        case 50:
            delegate?.overlayViewDidToggleCursor(self)
            return
        case 49:
            toolbarVisible.toggle()
            needsDisplay = true
            return
        case 43:
            stepHistory(forward: false)
            return
        case 47:
            stepHistory(forward: true)
            return
        case 48:
            windowDetectionEnabled.toggle()
            hoveredWindow = nil
            needsDisplay = true
            return
        case 123:
            nudge(dx: -1, dy: 0, modifiers: event.modifierFlags)
            return
        case 124:
            nudge(dx: 1, dy: 0, modifiers: event.modifierFlags)
            return
        case 125:
            nudge(dx: 0, dy: 1, modifiers: event.modifierFlags)
            return
        case 126:
            nudge(dx: 0, dy: -1, modifiers: event.modifierFlags)
            return
        default:
            break
        }

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "a":
            nudge(dx: -1, dy: 0, modifiers: event.modifierFlags)
        case "d":
            nudge(dx: 1, dy: 0, modifiers: event.modifierFlags)
        case "w":
            nudge(dx: 0, dy: -1, modifiers: event.modifierFlags)
        case "s":
            nudge(dx: 0, dy: 1, modifiers: event.modifierFlags)
        case "c" where event.modifierFlags.contains(.command):
            confirm()
        case "c" where !event.modifierFlags.contains(.command):
            copyColorAtPointer()
        case "a" where event.modifierFlags.contains(.command):
            state.select(bounds)
            hoveredWindow = nil
            needsDisplay = true
        case "r" where event.modifierFlags.contains(.command):
            rotateSelectedAnnotation()
        case "r":
            restoreLastSelection()
        case "t" where event.modifierFlags.contains(.command):
            requestPin()
        case "z" where event.modifierFlags.contains(.command) && event.modifierFlags.contains(.shift):
            annotationStack.redo()
            needsDisplay = true
        case "z" where event.modifierFlags.contains(.command):
            annotationStack.undo()
            needsDisplay = true
        case "s" where event.modifierFlags.contains([.command, .shift]):
            requestSave(quick: true)
        case "s" where event.modifierFlags.contains(.command):
            requestSave(quick: false)
        default:
            super.keyDown(with: event)
        }
    }

    override func flagsChanged(with event: NSEvent) {
        if event.modifierFlags.contains(.shift) {
            colorFormat = colorFormat == .hex ? .rgb : .hex
            needsDisplay = true
        }
    }

    // MARK: - 坐标

    private func localPoint(of event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }
}
