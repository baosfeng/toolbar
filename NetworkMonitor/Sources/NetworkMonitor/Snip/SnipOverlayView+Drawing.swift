import AppKit

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

    func drawHandles(_ rect: CGRect, in context: CGContext) {
        let size = Self.handleSize
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

    func drawSizeLabel(_ rect: CGRect) {
        let text = "\(Int(rect.width.rounded())) × \(Int(rect.height.rounded()))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let padding = NSSize(width: 6, height: 3)
        var origin = CGPoint(x: rect.minX, y: rect.minY - size.height - padding.height * 2 - 4)
        if origin.y < 0 { origin.y = rect.minY + 4 }
        let background = CGRect(x: origin.x, y: origin.y,
                                width: size.width + padding.width * 2,
                                height: size.height + padding.height * 2)
        sizeLabelFrame = background
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: background, xRadius: 3, yRadius: 3).fill()
        (text as NSString).draw(at: CGPoint(x: origin.x + padding.width, y: origin.y + padding.height),
                                withAttributes: attributes)
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

    /// 放大镜边长与采样跨度（点）
    static let magnifierSide: CGFloat = 120
    static let magnifierSpan: CGFloat = 15

    /// 在鼠标旁绘制像素放大镜：网格 + 中心像素框 + 坐标与色值
    func drawMagnifier(in context: CGContext) {
        guard let sampler else { return }
        let side = Self.magnifierSide
        let margin: CGFloat = 18
        var origin = CGPoint(x: pointer.x + margin, y: pointer.y + margin)
        if origin.x + side > bounds.width { origin.x = pointer.x - margin - side }
        if origin.y + side > bounds.height { origin.y = pointer.y - margin - side }
        origin.x = min(max(origin.x, 0), max(bounds.width - side, 0))
        origin.y = min(max(origin.y, 0), max(bounds.height - side, 0))

        let scale = CGFloat(screenshot.width) / max(bounds.width, 1)
        let span = Self.magnifierSpan
        let centerX = (pointer.x * scale).rounded()
        let centerY = (pointer.y * scale).rounded()
        let srcRect = CGRect(x: centerX - (span * scale) / 2,
                             y: centerY - (span * scale) / 2,
                             width: span * scale,
                             height: span * scale)
        guard let subImage = screenshot.cropping(to: srcRect) else { return }

        context.saveGState()
        context.setFillColor(NSColor.black.withAlphaComponent(0.85).cgColor)
        context.fill(CGRect(x: origin.x - 2, y: origin.y - 2, width: side + 4, height: side + 4))
        context.restoreGState()

        context.saveGState()
        context.translateBy(x: 0, y: 2 * origin.y + side)
        context.scaleBy(x: 1, y: -1)
        context.draw(subImage, in: CGRect(x: origin.x, y: origin.y, width: side, height: side))
        context.restoreGState()

        let cells = Int(span)
        let cell = side / CGFloat(cells)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.18).cgColor)
        context.setLineWidth(0.5)
        for index in 0...cells {
            let offset = CGFloat(index) * cell
            context.move(to: CGPoint(x: origin.x + offset, y: origin.y))
            context.addLine(to: CGPoint(x: origin.x + offset, y: origin.y + side))
            context.move(to: CGPoint(x: origin.x, y: origin.y + offset))
            context.addLine(to: CGPoint(x: origin.x + side, y: origin.y + offset))
        }
        context.strokePath()

        let centerCell = CGPoint(x: origin.x + side / 2 - cell / 2,
                                 y: origin.y + side / 2 - cell / 2)
        context.setStrokeColor(NSColor.systemRed.cgColor)
        context.setLineWidth(1.2)
        context.stroke(CGRect(x: centerCell.x, y: centerCell.y, width: cell, height: cell))

        let globalX = Int((pointer.x + displayOrigin.x).rounded())
        let globalY = Int((pointer.y + displayOrigin.y).rounded())
        var detail = "(\(globalX), \(globalY))"
        if let color = sampler.color(atPixel: CGPoint(x: centerX, y: centerY)) {
            detail += "  " + colorFormat.text(for: color)
        }
        drawLabel(detail, at: CGPoint(x: origin.x, y: origin.y + side + 4))
    }

}
