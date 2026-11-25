import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 标注操作提示（首次进标注态）

/// 第一次进标注态时在选区上方浮一条提示，3 秒后自动淡出
///
/// 为什么需要：本轮把滚轮从「一格一档」改成「连续 + 三档意图」之后，
/// 这些组合键对新用户是不可发现的 —— ⌘ 快调、⌥ 精调、⌃ 调透明度、⇧ 缩放图形，
/// 四条都没有任何可见入口。Snipaste 的做法是放大镜里常驻操作提示，
/// 我们放大镜已经很挤，改成「首次进标注态提示一次、看过就不再打扰」。
///
/// 只在第一次显示（偏好键 `snip.annotation.hintsShown`）：每次截图都弹会变成噪音。
@MainActor
final class SnipAnnotationHintsView: NSView {

    /// 提示内容（三段：滚轮 / 修饰键 / 精确输入）
    static let lines = [
    "滚轮调数值  ·  ⌘ 快调  ·  ⌥ 精调",
    "⌃ + 滚轮调透明度  ·  ⇧ + 滚轮缩放选中图形",
    "双击工具条数值 = 复位  ·  [ ] / 1 2 也能调"
    ]

    /// 内边距与行距
    private static let padding = CGSize(width: 12, height: 9)
    private static let lineGap: CGFloat = 3

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        setAccessibilityRole(.group)
        setAccessibilityLabel("标注操作提示" + SnipAnnotationHintsView.lines.joined(separator: "；"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("不支持从 nib 创建")
    }

    /// 按文案算尺寸（调用方据此摆放）
    static func size() -> CGSize {
        let width = lines.map { ($0 as NSString).size(withAttributes: attributes).width }.max() ?? 0
        let lineHeight = ("国" as NSString).size(withAttributes: attributes).height
        let height = lineHeight * CGFloat(lines.count) + lineGap * CGFloat(lines.count - 1)
        return CGSize(width: ceil(width) + padding.width * 2,
                      height: ceil(height) + padding.height * 2)
    }

    private static let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 11, weight: .regular),
        .foregroundColor: NSColor.white.withAlphaComponent(0.92)
    ]

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8)
        NSColor.black.withAlphaComponent(0.72).setFill()
        path.fill()
        let lineHeight = ("国" as NSString).size(withAttributes: Self.attributes).height
        var y = Self.padding.height
        for line in Self.lines {
            (line as NSString).draw(at: CGPoint(x: Self.padding.width, y: y),
                                    withAttributes: Self.attributes)
            y += lineHeight + Self.lineGap
        }
    }
}
