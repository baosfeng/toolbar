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
        case .number:
            drawNumber(annotation, in: context)
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
        let font = textFont(size: fontSize, style: annotation.style.text)
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

    /// 序号 = 实心圆底 + 居中白字（编号取 `annotation.text`）
    static func drawNumber(_ annotation: SnipAnnotation, in context: CGContext) {
        let rect = annotation.boundingRect
        let radius = min(rect.width, rect.height) / 2
        guard radius >= 2 else { return }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let color = annotation.style.color
        // 圆底用当前色；白/浅色底上的数字改用深色，避免白底白字看不见
        let isLight = (color.red + color.green + color.blue) / 3 > 0.75
        let textColor = isLight ? SnipAnnotationColor.black : SnipAnnotationColor.white
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: CGRect(x: center.x - radius,
                                       y: center.y - radius,
                                       width: radius * 2,
                                       height: radius * 2))
        let text = annotation.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // 两位及以上缩小字号，保证两位数不溢出圆
        let fontSize = radius * (text.count >= 2 ? 0.92 : 1.15)
        let font = CTFontCreateWithName("PingFang SC" as CFString, fontSize, nil)
        let attributed = NSAttributedString(string: text,
                                            attributes: [
                                                kCTFontAttributeName as NSAttributedString.Key: font,
                                                kCTForegroundColorAttributeName as NSAttributedString.Key: textColor.cgColor,
                                            ])
        let line = CTLineCreateWithAttributedString(attributed)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
        context.saveGState()
        // 外层坐标系 y 向下：基线要按 ascent/descent 折中到圆心，再局部翻转画正向字
        context.translateBy(x: center.x - width / 2, y: center.y + (ascent - descent) / 2)
        context.scaleBy(x: 1, y: -1)
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }

    /// 文字标注的字体：按字体族与字重挑一个系统字体
    ///
    /// 中文字重走 system font 的 traits 才能真的加粗（PingFang 的粗体是另一条字重轴），
    /// 因此这里不直接 `CTFontCreateWithName("PingFang SC Bold")`，而是拿系统字体再叠 trait。
    public static func textFont(size: CGFloat, style: SnipTextStyle) -> CTFont {
        var attributes: [CFString: Any] = [kCTFontSizeAttribute: size]
        if let family = Self.familyName(for: style.family) {
            attributes[kCTFontFamilyNameAttribute] = family
        }
        if style.bold {
            attributes[kCTFontTraitsAttribute] = [kCTFontWeightTrait: 0.4]
        }
        let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
        // 族名不存在时 CTFont 会回落到系统默认字体，不会返回 nil，因此这里不必再判空
        let base = CTFontCreateWithFontDescriptor(descriptor, size, nil)
        guard style.bold else { return base }
        // 字重 trait 在部分族上不生效（族只有 Regular 一档时描述符会被忽略），
        // 因此再加一道 symbolic traits 复制：这是 AppKit / CoreText 里真正会切字形的路径。
        return CTFontCreateCopyWithSymbolicTraits(base, size, nil, .boldTrait, .boldTrait) ?? base
    }

    /// 字体族 → 系统里必然存在的族名；nil 表示「不指定族，用系统默认」
    ///
    /// 都选随 macOS 一起安装的中文字体：第三方字体在别人机器上不存在会让字号与换行口径全都变。
    public static func familyName(for family: SnipTextFamily) -> String? {
        switch family {
        case .system: return nil
        case .rounded: return "Yuanti SC"
        case .monospaced: return "Menlo"
        case .serif: return "Songti SC"
        }
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
        if annotation.kind == .number {
            // 序号按整圆命中：点在圆内即算命中（圆比外接框小，不能直接套矩形容差）
            let rect = annotation.boundingRect
            let radius = min(rect.width, rect.height) / 2 + tolerance
            return distance(CGPoint(x: rect.midX, y: rect.midY), point) <= radius
        }
        let rect = annotation.boundingRect.insetBy(dx: -tolerance, dy: -tolerance)
        guard rect.contains(point) else { return false }
        switch annotation.kind {
        case .rectangle, .ellipse, .mosaic, .blur, .text, .number:
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
