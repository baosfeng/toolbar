import AppKit
import NetworkMonitorCore

// MARK: - 工具条基础绘制

/// 工具条与二级面板共用的按钮画法
///
/// 一级工具条与二级面板要画同一套按钮（选中态的圆角底、SF Symbols、颜色圆点、线宽条），
/// 抽到这里避免两处各写一遍——早期工具条宽度与布局就是这么分叉出 17pt 空白的。
enum SnipBarDrawing {

    /// 画一个工具按钮（SF Symbol，白色）
    static func drawTool(_ tool: SnipTool, in rect: CGRect, alpha: CGFloat) {
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        guard let image = NSImage(systemSymbolName: tool.symbolName,
                                  accessibilityDescription: tool.displayName)?
            .withSymbolConfiguration(configuration) else {
            return
        }
        image.draw(in: rect.insetBy(dx: 6, dy: 6), from: .zero, operation: .sourceOver, fraction: alpha)
    }

    /// 画一个颜色圆点（选中时加白色描边环）
    static func drawColorDot(_ color: SnipAnnotationColor, in rect: CGRect, isSelected: Bool) {
        let dotRect = rect.insetBy(dx: 3, dy: 3)
        NSColor(cgColor: color.cgColor)?.setFill()
        NSBezierPath(ovalIn: dotRect).fill()
        guard isSelected else { return }
        NSColor.white.withAlphaComponent(0.95).setStroke()
        let ring = NSBezierPath(ovalIn: dotRect.insetBy(dx: -2, dy: -2))
        ring.lineWidth = 1.5
        ring.stroke()
    }

    /// 画一档线宽（一条按线宽值加粗的短横线）
    static func drawWidth(_ width: CGFloat, in rect: CGRect, isSelected: Bool) {
        let lineRect = CGRect(x: rect.minX + 5,
                              y: rect.midY - width / 2,
                              width: rect.width - 10,
                              height: width)
        NSColor.white.withAlphaComponent(isSelected ? 1 : 0.7).setFill()
        NSBezierPath(roundedRect: lineRect, xRadius: width / 2, yRadius: width / 2).fill()
    }
}
