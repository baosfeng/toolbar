import AppKit
import NetworkMonitorCore

// MARK: - 鼠标交互（从主类拆出，守住单文件门禁）

/// 覆盖层的鼠标处理 — 悬停探测窗口、拖拽选区、右键收笔 / 中止、中键贴图、滚轮调样式
///
/// 拆出原因：主文件此前已经同时装着绘制入口、键盘分发与状态字段，逼近 15 KiB 门禁。
/// 这里只保留「鼠标事件 → 状态机调用」这一层，判定逻辑仍在各自的扩展文件里。
extension SnipOverlayView {

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
        // 二级面板展开时，点面板外等于「收起面板」：不把这一下当成新建选区，
        // 否则用户想关面板却顺手把选区清掉了
        if let panel = toolPanel {
            if panel.frame.contains(point) { return }
            closeToolPanel()
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
        if handleAnnotationMouseDragged(to: point, lockingShift: event.modifierFlags.contains(.shift)) { return }
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

    /// 右键语义分离：编辑态只收笔（截图与已有标注都保留），非编辑态才中止整次截图。
    /// 判定口径见 SnipRightClickIntent（官方两张键位表对右键给了不同含义）。
    override func rightMouseDown(with event: NSEvent) {
        handleRightClick()
    }

    /// 滚轮：选中文字时改字号，处于标注模式时改画笔粗细（官方把滚轮列为调粗细的通路之一）
    override func scrollWheel(with event: NSEvent) {
        if handleStyleScroll(event) { return }
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
}
