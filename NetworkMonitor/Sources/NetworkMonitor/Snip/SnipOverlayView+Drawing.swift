import AppKit
import NetworkMonitorCore

// MARK: - 绘制（从主类拆出，守住单文件 500 行 / 15 KiB 门禁）

extension SnipOverlayView {

    func drawScreenshot(in context: CGContext) {
        context.saveGState()
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        context.draw(screenshot, in: CGRect(origin: .zero, size: bounds.size))
        context.restoreGState()
    }

    func drawBorder(_ rect: CGRect, in context: CGContext) {
        context.saveGState()
        context.setStrokeColor(NSColor.systemBlue.cgColor)
        context.setLineWidth(Self.frameLineWidth)
        context.stroke(rect.insetBy(dx: 0.5, dy: 0.5))
        context.restoreGState()
    }

    /// 八个调整锚点（8pt 白块 + 蓝描边）
    ///
    /// 任一边不足 5 个锚点宽（40pt）时不画：12×10 这类小选区上 8pt 白块会连成一片，
    /// 把要取的像素整片盖住。判定与命中测试同源（`SelectionGeometry.shouldShowHandles`），
    /// 所以不会留下「看不见却还能拖」的把手。
    func drawHandles(_ rect: CGRect, in context: CGContext) {
        let size = Self.handleSize
        guard SelectionGeometry.shouldShowHandles(for: rect, handleSize: size) else { return }
        let centers = [
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.midX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.minX, y: rect.midY),
            CGPoint(x: rect.maxX, y: rect.midY), CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.midX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)
        ]
        context.setFillColor(NSColor.white.cgColor)
        context.setStrokeColor(NSColor.systemBlue.cgColor)
        context.setLineWidth(1)
        for center in centers {
            let box = CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
            context.fill(box)
            context.stroke(box)
        }
    }

    /// 尺寸标签：`宽 x 高` 深色胶囊 + 指向选区的小三角
    ///
    /// 默认贴在选区上方、三角朝下指向选区；选区贴到屏幕上沿放不下时翻进选区内部、三角朝上。
    /// 三角画在胶囊矩形**之外**：`sizeLabelFrame` 是「点它就进尺寸输入」的命中区，
    /// 把三角算进去等于让用户点三角也弹输入框。
    func drawSizeLabel(_ rect: CGRect) {
        let arrowHeight: CGFloat = 4
        let text = SnipPanelLabelText.size(width: rect.width, height: rect.height)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let padding = NSSize(width: 6, height: 3)
        var pointingDown = true
        var origin = CGPoint(x: rect.minX,
                             y: rect.minY - size.height - padding.height * 2 - arrowHeight)
        if origin.y < arrowHeight {
            // 屏幕顶部放不下：翻进选区内部，三角改成朝上，仍然咬住选区上边界
            origin.y = rect.minY + arrowHeight
            pointingDown = false
        }
        let background = CGRect(x: origin.x, y: origin.y,
                                width: size.width + padding.width * 2,
                                height: size.height + padding.height * 2)
        sizeLabelFrame = background
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: background, xRadius: 3, yRadius: 3).fill()
        (text as NSString).draw(at: CGPoint(x: origin.x + padding.width, y: origin.y + padding.height),
                                withAttributes: attributes)

        let arrow = SnipPanelLabelText.sizeLabelArrowPoints(pointingDown: pointingDown,
                                                            labelFrame: background,
                                                            selection: rect,
                                                            height: arrowHeight)
        guard arrow.count == 3 else { return }
        let path = NSBezierPath()
        path.move(to: arrow[0])
        path.line(to: arrow[1])
        path.line(to: arrow[2])
        path.close()
        NSColor.black.withAlphaComponent(0.7).setFill()
        path.fill()
    }

    func drawCrosshair(in context: CGContext) {
        context.saveGState()
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.6).cgColor)
        context.setLineWidth(0.5)
        context.move(to: CGPoint(x: pointer.x, y: 0))
        context.addLine(to: CGPoint(x: pointer.x, y: bounds.height))
        context.move(to: CGPoint(x: 0, y: pointer.y))
        context.addLine(to: CGPoint(x: bounds.width, y: pointer.y))
        context.strokePath()
        context.restoreGState()
    }

    // MARK: - 放大镜

    /// 在鼠标旁绘制像素放大镜（网格 / 中心像素框 / 坐标与色值两行信息条）
    ///
    /// 绘制细节与放大镜自己的常量都在 `SnipMagnifierDrawing`：这里只做一次状态搬运，
    /// 绘制扩展不再因为放大镜长身体。
    func drawMagnifier(in context: CGContext) {
        SnipMagnifierDrawing.draw(in: context, state: SnipMagnifierDrawing.State(
            screenshot: screenshot,
            sampler: sampler,
            pointer: pointer,
            bounds: bounds,
            displayOrigin: displayOrigin,
            colorFormat: colorFormat))
    }

}
