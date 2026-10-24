import CoreGraphics
import CoreText
import Foundation

// MARK: - 标注渲染

/// 标注渲染 — 输入本地点坐标（左上原点），调用方负责把 CTM 调整为左上原点
public enum SnipAnnotationRenderer {

    public static func draw(_ annotations: [SnipAnnotation], in context: CGContext) {
        for annotation in annotations {
            draw(annotation, in: context)
        }
    }

    public static func draw(_ annotation: SnipAnnotation, in context: CGContext) {
        guard !annotation.isDegenerate() else { return }
        let style = annotation.style
        context.saveGState()
        context.setStrokeColor(style.color.cgColor)
        context.setFillColor(style.color.cgColor)
        context.setLineWidth(style.lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        if style.dashed {
            context.setLineDash(phase: 0, lengths: [style.lineWidth * 3, style.lineWidth * 2])
        }

        switch annotation.kind {
        case .rectangle:
            let rect = annotation.boundingRect
            if style.filled {
                context.fill(rect)
            } else {
                context.stroke(rect)
            }
        case .ellipse:
            let rect = annotation.boundingRect
            if style.filled {
                context.fillEllipse(in: rect)
            } else {
                context.strokeEllipse(in: rect)
            }
        case .line:
            context.move(to: annotation.start)
            context.addLine(to: annotation.end)
            context.strokePath()
        case .arrow:
            drawArrow(from: annotation.start, to: annotation.end, lineWidth: style.lineWidth, in: context)
        case .mosaic, .blur:
            // 需要底图像素，交由 SnipAnnotationCompositor 处理
            break
        case .text:
            drawText(annotation, in: context)
        case .freehand, .polyline:
            guard let first = annotation.points.first, annotation.points.count >= 2 else { break }
            context.move(to: first)
            for point in annotation.points.dropFirst() {
                context.addLine(to: point)
            }
            context.strokePath()
        }
        context.restoreGState()
    }

    /// 文字 = CoreText 单行绘制；左上角为锚点
    static func drawText(_ annotation: SnipAnnotation, in context: CGContext) {
        let trimmed = annotation.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let fontSize = annotation.fontSize
        let font = CTFontCreateWithName("PingFang SC" as CFString, fontSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            kCTFontAttributeName as NSAttributedString.Key: font,
            kCTForegroundColorAttributeName as NSAttributedString.Key: annotation.style.color.cgColor
        ]
        let attributed = NSAttributedString(string: trimmed, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributed)
        context.saveGState()
        // 翻转局部坐标，让文字正向显示；再按需绕锚点旋转
        context.translateBy(x: annotation.start.x, y: annotation.start.y + fontSize)
        if annotation.rotation != 0 {
            context.rotate(by: annotation.rotation)
        }
        context.scaleBy(x: 1, y: -1)
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }

    /// 文字在给定字号下的包围盒（单行）
    public static func textSize(_ text: String, fontSize: CGFloat) -> CGSize {
        let font = CTFontCreateWithName("PingFang SC" as CFString, fontSize, nil)
        let attributed = NSAttributedString(string: text,
                                            attributes: [kCTFontAttributeName as NSAttributedString.Key: font])
        let line = CTLineCreateWithAttributedString(attributed)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
        return CGSize(width: width, height: ascent + descent)
    }

    /// 箭头 = 主线 + 两条对称的箭头边
    static func drawArrow(from start: CGPoint, to end: CGPoint, lineWidth: CGFloat, in context: CGContext) {
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()

        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength = max(lineWidth * 4, 10)
        let spread = CGFloat.pi / 7
        let left = CGPoint(x: end.x - headLength * cos(angle - spread),
                           y: end.y - headLength * sin(angle - spread))
        let right = CGPoint(x: end.x - headLength * cos(angle + spread),
                            y: end.y - headLength * sin(angle + spread))
        context.move(to: end)
        context.addLine(to: left)
        context.move(to: end)
        context.addLine(to: right)
        context.strokePath()
    }

    // MARK: - 命中与擦除

    /// 点是否落在某条标注附近（橡皮擦按点删除）
    public static func hitTest(_ annotation: SnipAnnotation, point: CGPoint, tolerance: CGFloat = 8) -> Bool {
        if annotation.kind == .text {
            let size = textSize(annotation.text, fontSize: annotation.fontSize)
            let textRect = CGRect(origin: annotation.start, size: size)
                .insetBy(dx: -tolerance, dy: -tolerance)
            return textRect.contains(point)
        }
        let rect = annotation.boundingRect.insetBy(dx: -tolerance, dy: -tolerance)
        guard rect.contains(point) else { return false }
        switch annotation.kind {
        case .rectangle, .ellipse, .mosaic, .blur, .text:
            return true
        case .freehand:
            return annotation.points.contains { distance($0, point) <= tolerance }
        case .polyline:
            guard annotation.points.count >= 2 else { return false }
            for index in 0..<(annotation.points.count - 1)
            where distanceToSegment(point, annotation.points[index], annotation.points[index + 1]) <= tolerance {
                return true
            }
            return false
        case .line, .arrow:
            return distanceToSegment(point, annotation.start, annotation.end) <= tolerance
        }
    }

    /// 轨迹上距离目标点最近的点下标（容差内），用于局部擦除
    public static func nearestPointIndex(in points: [CGPoint],
                                         to point: CGPoint,
                                         tolerance: CGFloat = 10) -> Int? {
        guard !points.isEmpty else { return nil }
        var bestIndex: Int?
        var bestDistance = tolerance
        for (index, candidate) in points.enumerated() {
            let value = distance(candidate, point)
            if value <= bestDistance {
                bestDistance = value
                bestIndex = index
            }
        }
        return bestIndex
    }

    public static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x, dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }

    public static func distanceToSegment(_ point: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return distance(point, a) }
        let t = max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared))
        let projection = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
        return distance(point, projection)
    }
}
