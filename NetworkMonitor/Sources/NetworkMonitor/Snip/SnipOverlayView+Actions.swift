import AppKit
import NetworkMonitorCore

// MARK: - 交互动作（从主类拆出，守住单文件门禁）

extension SnipOverlayView {

// MARK: - 动作

    func confirm() {
        guard let selection = state.selection else { return }
        delegate?.overlayView(self, didConfirm: selection)
    }

    func requestPin() {
        guard let selection = state.selection else { return }
        delegate?.overlayView(self, didRequestPin: selection)
    }

    func requestSave(quick: Bool) {
        guard let selection = state.selection else { return }
        delegate?.overlayView(self, didRequestSave: selection, quick: quick)
    }

    // MARK: - 精确尺寸输入

    /// 弹出输入框，输入 800x600 这样的尺寸后按回车应用
    func beginSizeEditing() {
        guard sizeEditor == nil, state.phase == .selected else { return }
        let width: CGFloat = 132
        let field = SizeEditorField(frame: CGRect(x: sizeLabelFrame.minX,
                                                  y: sizeLabelFrame.minY,
                                                  width: width,
                                                  height: 22))
        field.stringValue = "\(Int(state.rect.width.rounded()))x\(Int(state.rect.height.rounded()))"
        field.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        field.bezelStyle = .roundedBezel
        field.focusRingType = .none
        field.target = self
        field.action = #selector(commitSizeEditing)
        field.onCancel = { [weak self] in self?.endSizeEditing(apply: false) }
        addSubview(field)
        sizeEditor = field
        window?.makeFirstResponder(field)
        field.selectText(nil)
        needsDisplay = true
    }

    @objc func commitSizeEditing() {
        endSizeEditing(apply: true)
    }

    func endSizeEditing(apply: Bool) {
        guard let field = sizeEditor else { return }
        let text = field.stringValue
        field.removeFromSuperview()
        sizeEditor = nil
        window?.makeFirstResponder(self)
        defer { needsDisplay = true }
        guard apply, let size = SnipSizeInput.parse(text) else { return }
        let anchor = state.rect.origin
        var rect = CGRect(x: anchor.x, y: anchor.y, width: size.width, height: size.height)
        if rect.maxX > bounds.width { rect.origin.x = max(bounds.width - size.width, 0) }
        if rect.maxY > bounds.height { rect.origin.y = max(bounds.height - size.height, 0) }
        rect.origin.x = max(rect.origin.x, 0)
        rect.origin.y = max(rect.origin.y, 0)
        state.select(rect)
    }

    /// 取鼠标所在像素的颜色并写入剪贴板
    func copyColorAtPointer() {
        guard let sampler else { return }
        let scale = CGFloat(screenshot.width) / max(bounds.width, 1)
        let pixel = CGPoint(x: pointer.x * scale, y: pointer.y * scale)
        guard let color = sampler.color(atPixel: pixel) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(colorFormat.text(for: color), forType: .string)
    }


    /// 在最近成功截图的选区之间循环（逗号向更早、句号向更新）
    func stepHistory(forward: Bool) {
        guard !history.isEmpty else { return }
        let count = history.count
        var index = historyIndex ?? -1
        index += forward ? 1 : -1
        if index >= count { index = 0 }
        if index < 0 { index = count - 1 }
        historyIndex = index
        applyGlobalSelection(history[index])
    }

    /// 把全局选区裁到本屏并应用
    func applyGlobalSelection(_ rect: CGRect) {
        let local = rect.offsetBy(dx: -displayOrigin.x, dy: -displayOrigin.y)
        let clipped = local.intersection(bounds)
        guard !clipped.isNull, clipped.width >= 1, clipped.height >= 1 else { return }
        state.select(clipped)
        hoveredWindow = nil
        needsDisplay = true
    }

    /// 恢复上次成功截图的范围（只取与本屏交叠部分）
    func restoreLastSelection() {
        guard let lastSelection else { return }
        applyGlobalSelection(lastSelection)
    }

    func nudge(dx: CGFloat, dy: CGFloat, modifiers: NSEvent.ModifierFlags) {
        guard state.phase == .selected else { return }
        if modifiers.contains(.control) {
            state.expand(by: max(abs(dx), abs(dy)))
        } else if modifiers.contains(.shift) {
            state.shrink(by: max(abs(dx), abs(dy)))
        } else {
            state.move(by: CGSize(width: dx, height: dy))
        }
        needsDisplay = true
    }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        layoutToolBar()
        drawScreenshot(in: context)

        context.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor)
        context.fill(bounds)

        let activeRect: CGRect? = state.selection
            ?? (state.phase == .dragging && state.rect.width > 0 && state.rect.height > 0 ? state.rect : nil)

        if let rect = activeRect {
            context.saveGState()
            context.clip(to: rect)
            drawScreenshot(in: context)
            context.restoreGState()
            drawAnnotations(in: context, clip: rect)
            drawBorder(rect, in: context)
            drawHandles(rect, in: context)
            drawSizeLabel(rect)
        } else if state.phase == .idle {
            drawCrosshair(in: context)
            drawHoveredWindow(in: context)
        }

        if state.phase != .selected {
            drawMagnifier(in: context)
        }
    }

    /// 高亮鼠标下的窗口，并标出所属应用
    func drawHoveredWindow(in context: CGContext) {
        guard let hovered = hoveredWindow else { return }
        let local = hovered.frame.offsetBy(dx: -displayOrigin.x, dy: -displayOrigin.y)
        context.saveGState()
        context.setFillColor(NSColor.systemBlue.withAlphaComponent(0.15).cgColor)
        context.fill(local)
        context.setStrokeColor(NSColor.systemBlue.cgColor)
        context.setLineWidth(2)
        context.stroke(local.insetBy(dx: 1, dy: 1))
        context.restoreGState()
        let label = hovered.title.isEmpty ? hovered.ownerName : "\(hovered.ownerName) — \(hovered.title)"
        drawLabel(label, at: CGPoint(x: local.minX + 4, y: local.minY + 4))
    }

    /// 左上角小标签（黑底白字）
    /// 放宽为 internal：绘制扩展文件（放大镜）也要用
    func drawLabel(_ text: String, at point: CGPoint) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let padding = NSSize(width: 5, height: 2)
        let background = CGRect(x: point.x, y: point.y,
                                width: size.width + padding.width * 2,
                                height: size.height + padding.height * 2)
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: background, xRadius: 3, yRadius: 3).fill()
        (text as NSString).draw(at: CGPoint(x: point.x + padding.width, y: point.y + padding.height),
                                withAttributes: attributes)
    }

    /// 换一张截图（切换指针显示时由编排方重新捕获后回灌）
    func updateScreenshot(_ image: CGImage) {
        screenshot = image
        sampler = SnipPixelSampler(image: image)
        needsDisplay = true
    }

    /// 整屏成立选区（白板模式进入时用）
    ///
    /// 注意：这是生产路径方法，不能放进 DEBUG 条件编译块 —— 否则 release 构建里
    /// 白板模式的调用点会编译失败（v1.7.0 的 GitHub Release 就是因此在打包步骤挂了）。
    func selectFullBoard() {
        state.select(bounds)
        hoveredWindow = nil
        needsDisplay = true
    }

    #if DEBUG
    /// 仅 DEBUG：程序化把鼠标位置挪到某点，触发窗口检测与放大镜
    func debugHover(atLocalPoint point: CGPoint) {
        pointer = point
        updateHoveredWindow()
        needsDisplay = true
    }

    /// 仅 DEBUG：程序化添加一条标注，供实机截图取证
    func debugAddAnnotation(_ annotation: SnipAnnotation) {
        annotationStack.add(annotation)
        needsDisplay = true
    }

    /// 仅 DEBUG：程序化摆一个选区，供实机截图取证
    func debugApplySelection(_ rect: CGRect) {
        state.begin(at: rect.origin)
        state.drag(to: CGPoint(x: rect.maxX, y: rect.maxY))
        state.end()
        needsDisplay = true
    }
    #endif
}
