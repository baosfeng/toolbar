import AppKit

// MARK: - 图表绘制辅助

/// Token 页图表共用绘制工具 —— 文字、斜纹、细线
@MainActor
enum TokenChartSupport {

    /// 绘制单行文字（rect 内按对齐方式垂直居中）
    static func draw(_ text: String,
                     font: NSFont,
                     color: NSColor,
                     in rect: NSRect,
                     alignment: NSTextAlignment = .left) {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = .byClipping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: style,
        ]
        (text as NSString).draw(in: rect, withAttributes: attributes)
    }

    /// 斜纹填充（缺省小时 / 无会话日）—— 135° 细线，裁剪在 rect 内
    static func drawHatch(in rect: NSRect, color: NSColor, spacing: CGFloat = 3) {
        guard rect.width > 0, rect.height > 0 else { return }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        let path = NSBezierPath()
        path.lineWidth = 1
        var offset = -rect.height
        while offset < rect.width + rect.height {
            path.move(to: NSPoint(x: rect.minX + offset, y: rect.minY))
            path.line(to: NSPoint(x: rect.minX + offset + rect.height, y: rect.maxY))
            offset += spacing
        }
        color.setStroke()
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }
}
