import AppKit
import NetworkMonitorUI

// MARK: - 卡片表面（圆角底 / 叠色 / 描边）

/// 卡片表面 —— 一层「圆角底 + 可选描边」，参数化后三处卡片共用一份绘制
///
/// 抽出来的理由：同一个「圆角矩形填充」被写了三遍（`DrawnCard` 走 `DrawnInk.fill`、
/// 系统页五卡走 `NSBezierPath` + wash、剪贴板卡走「卡底 + 两层叠色描边」），
/// 换主题 / 调圆角时要在三处同步改。抽成值类型后：矩形、圆角、填充、描边、过渡不透明度
/// 全部由调用方给，绘制只有一条路径。
///
/// 路径统一用 `NSBezierPath(roundedRect:xRadius:yRadius:)`：实测与本项目原 `DrawnInk.fill`
/// 的 `CGPath(roundedRect:)` 填充逐像素相同（60×60 圆角矩形 0px 差），
/// 而描边两者不同（同矩形同线宽 104px 抗锯齿差），故描边一律沿用本 API。
package struct DrawnCardSurface {

    /// 表面矩形（需要内缩描边时由调用方先行 `insetBy`）
    var rect: CGRect
    /// 圆角半径
    var radius: CGFloat
    /// 填充色（nil = 只描边）
    var fill: NSColor?
    /// 描边色（nil = 不描边）
    var stroke: NSColor?
    /// 描边线宽
    var lineWidth: CGFloat = 0
    /// 整层不透明度（过渡值：1 = 常态；≤ 0.001 时整层不画）
    var alpha: CGFloat = 1

    package init(rect: CGRect,
         radius: CGFloat,
         fill: NSColor? = nil,
         stroke: NSColor? = nil,
         lineWidth: CGFloat = 0,
         alpha: CGFloat = 1) {
        self.rect = rect
        self.radius = radius
        self.fill = fill
        self.stroke = stroke
        self.lineWidth = lineWidth
        self.alpha = alpha
    }

    /// 画这一层：填充 → 描边（同一路径，与改造前的视图绘制逐像素同源）
    package func draw() {
        guard DrawnLayerAlpha.isVisible(alpha), rect.width > 0, rect.height > 0 else { return }
        guard fill != nil || stroke != nil else { return }
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        if let fill {
            Self.color(fill, layerAlpha: alpha).setFill()
            path.fill()
        }
        guard let stroke, lineWidth > 0 else { return }
        Self.color(stroke, layerAlpha: alpha).setStroke()
        path.lineWidth = lineWidth
        path.stroke()
    }

    /// 按层不透明度折算颜色
    ///
    /// 层 alpha 为 1（常态）时原样返回：语义色（labelColor / selectedFill 这类动态色）
    /// 一旦套 `withAlphaComponent` 就不再是同一个颜色对象，留原样可让动态解析路径与改造前完全一致。
    private static func color(_ color: NSColor, layerAlpha: CGFloat) -> NSColor {
        let alpha = DrawnLayerAlpha.fold(color.alphaComponent, layer: layerAlpha)
        guard abs(alpha - color.alphaComponent) > 0.0001 else { return color }
        return color.withAlphaComponent(alpha)
    }
}
