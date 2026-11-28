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
        // 取色板与二级面板一样：点面板外 = 收起，且不把这一下当成新建选区
        if let picker = colorPicker {
            if picker.frame.contains(point) { return }
            closeColorPicker()
            return
        }
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
            // 拖拽中按过空格 = 移动选区而不是继续拉边（Snipaste 高级技巧同款）
            if state.isSpaceMoving {
                state.spaceMove(to: point)
            } else {
                state.drag(to: point)
            }
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

    /// 松开空格 = 退出「移动选区」，把拖拽锚点钉在当前位置，继续往外拉仍然连贯
    ///
    /// 空格是普通键不是修饰键，收不到 flagsChanged，只能靠 keyUp 判定松手。
    /// 拖拽过程中 AppKit 仍会把 keyUp 送到覆盖层（它此时是 first responder）。
    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49, state.isSpaceMoving {
            state.exitSpaceMove(at: pointer)
            needsDisplay = true
            return
        }
        super.keyUp(with: event)
    }

    override func flagsChanged(with event: NSEvent) {
        if event.modifierFlags.contains(.shift) {
            colorFormat = colorFormat == .hex ? .rgb : .hex
            needsDisplay = true
        }
    }

    /// 滚轮：唯一入口交给数值调整（见 SnipNumericController）
    ///
    /// 早期这里是两条互相打架的通路：handleStyleScroll 走档位吸附、
    /// 下面这段走「选中文字改 fontScale」。结果是同一个滚轮在两种状态下
    /// 手感完全不同（一个有档位、一个 3% 连续），而且都不落偏好。
    /// 现在统一成「选了什么就调什么」，步长与范围都来自 SnipNumericParam。
    override func scrollWheel(with event: NSEvent) {
        // 总开关关掉时整条通路放行，不只跳过数值调整：
        // 半开半关会让人分不清「滚轮在这个界面到底能不能用」
        guard scrollAdjustEnabled else {
            super.scrollWheel(with: event)
            return
        }
        if numeric.handleScroll(event) { return }
        super.scrollWheel(with: event)
    }
}