import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

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
    /// 点击与拖拽的判定阈值（点）：位移超过它就不再算「单击选窗」
    static let clickTolerance: CGFloat = SnipPointerGesture.clickTolerance

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
    /// 首帧重绘尝试次数（只在拿不到绘图上下文时自增，用于终止重试）
    var redrawAttempts = 0
    /// 是否有输入框正在编辑（此时按键要让给输入框）
    var hasActiveTextInput: Bool { sizeEditor != nil || textEditor != nil }
    /// 本次按下时的落点（用于区分单击选窗与拖拽选区）
    private var pressPoint: CGPoint?
    /// 本次按下时悬停的窗口（松手且位移很小时用它成立整窗选区）
    private var pressedWindow: SnipWindowInfo?

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

    /// 中键点击选区 = 直接贴到屏幕上（Snipaste 的 Ctrl+T 等价操作，鼠标党常用）
    override func otherMouseDown(with event: NSEvent) {
        let point = localPoint(of: event)
        guard state.phase == .selected, state.rect.contains(point) else { return }
        requestPin()
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
        // 双击选区 = 复制（Snipaste 的高频动作，用户习惯双击就完成）
        if event.clickCount == 2, state.phase == .selected, state.rect.contains(point) {
            confirm()
            return
        }
        if handleAnnotationMouseDown(at: point) { return }
        if let handle = state.hitTest(point, handleSize: Self.handleSize) {
            state.beginAdjust(handle, at: point)
        } else {
            // 按下时一律进入拖拽，不在 mouseDown 里直接选中整窗：
            // 早期实现在 hover 到窗口时立刻成立整窗选区，用户想拖任意区域时
            // 鼠标一按下就被判成「点选窗口」，于是只能整窗截图、画不出自定义选区。
            // 现在改成「按下开始拖、松手时位移小于阈值才算点选窗口」，
            // 也就是 Snipaste 的语义：悬停高亮窗口，单击选整窗，拖拽选任意区域。
            pressPoint = point
            pressedWindow = state.phase == .idle ? hoveredWindow : nil
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
            applyClickSelectionIfNeeded(at: localPoint(of: event))
        } else {
            state.endAdjust()
        }
        needsDisplay = true
    }

    /// 松手时若位移小于阈值，且按下时悬停在某个窗口上，就判定为「单击选窗」
    ///
    /// 阈值取 4 点：触控板轻微抖动不至于把点击误判成拖拽，
    /// 而用户真正想拖选区时位移必然远大于 4 点。
    private func applyClickSelectionIfNeeded(at point: CGPoint) {
        guard let window = pressedWindow, let pressPoint else { return }
        defer {
            self.pressPoint = nil
            pressedWindow = nil
        }
        guard SnipPointerGesture.outcome(start: pressPoint, end: point, hasHoveredWindow: true)
            == .clickWindow else { return }
        let local = window.frame.offsetBy(dx: -displayOrigin.x, dy: -displayOrigin.y)
        state.select(local)
        hoveredWindow = nil
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

    /// Esc 先被 AppKit 的「取消」链路吃掉，不会进 keyDown
    ///
    /// Esc 走的是 cancelOperation(_:)：只有 SizeEditorField 覆写过它，主视图不覆写时
    /// Esc 会被静默吞掉——用户按 Esc 关不掉覆盖层，症状与「截图键毫无反应」同类。
    override func cancelOperation(_ sender: Any?) {
        delegate?.overlayViewDidCancel(self)
    }

    override func keyDown(with event: NSEvent) {
        handleKeyEvent(event)
    }

    /// 统一处理一次按键（窗口 keyDown 与兜底监视器共用同一份逻辑）
    ///
    /// 兜底路径的意义：菜单栏 App 拿不到系统级前台时，AppKit 仍会把事件送到本进程，
    /// 但可能不派给任何一个窗口。此时靠 NSApp 本地监视器把事件转进来，
    /// 覆盖层才不会出现「窗口在屏上、按键全无反应」。
    func handleKeyEvent(_ event: NSEvent) {
        let modifiers = SnipKeyCommandResolver.Modifiers(nsEventFlags: event.modifierFlags)
        let command = SnipKeyCommandResolver.resolve(keyCode: Int(event.keyCode),
                                                     characters: event.charactersIgnoringModifiers,
                                                     modifiers: modifiers)
        if perform(command, modifiers: event.modifierFlags) { return }
        super.keyDown(with: event)
    }

    /// 执行一条键位命令；返回 true 表示已处理（false 时交回系统）
    ///
    /// 键位解析搬到 NetworkMonitorUI 的纯函数后，带 ⌘ 的组合不会被裸字母分支吃掉，
    /// 且有断言守着顺序（早期实现里 ⌘S / ⌘A 从来没生效过）。
    private func perform(_ command: SnipKeyCommand, modifiers: NSEvent.ModifierFlags) -> Bool {
        switch command {
        case .cancel:
            // Esc 一律结束截图：早期实现先清「选中标注 / 未完成草稿」，用户以为 Esc 没反应
            // （画完箭头想取消要按第二下），而悬停残留的 draft 还会让取消彻底失效。
            // 现在直接取消整次截图——这与 Snipaste「Esc 随时中止」的语义一致。
            selectedAnnotationIndex = nil
            draftAnnotation = nil
            delegate?.overlayViewDidCancel(self)
        case .confirm:
            if finishPolylineDraft() { return true }
            confirm()
        case .toggleCursor:
            delegate?.overlayViewDidToggleCursor(self)
        case .toggleToolBar:
            toolbarVisible.toggle()
            needsDisplay = true
        case .historyOlder:
            stepHistory(forward: false)
        case .historyNewer:
            stepHistory(forward: true)
        case .toggleWindowDetection:
            windowDetectionEnabled.toggle()
            hoveredWindow = nil
            needsDisplay = true
        case .nudge(let dx, let dy):
            nudge(dx: dx, dy: dy, modifiers: modifiers)
        case .copyColor:
            copyColorAtPointer()
        case .selectAll:
            state.select(bounds)
            hoveredWindow = nil
            needsDisplay = true
        case .rotateSelectedText:
            rotateSelectedAnnotation()
        case .restoreLastSelection:
            restoreLastSelection()
        case .pin:
            requestPin()
        case .undo:
            annotationStack.undo()
            needsDisplay = true
        case .redo:
            annotationStack.redo()
            needsDisplay = true
        case .save(let quick):
            requestSave(quick: quick)
        case .copyImage:
            confirm()
        case .none:
            return false
        }
        return true
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
