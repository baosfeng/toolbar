import AppKit
import NetworkMonitorCore

// MARK: - 主图左侧刻度（从 TokenChartViews.swift 拆出：单文件体积门禁）

/// 刻度栏绘制与宽度计算 —— 与柱高同一归一化基准，不另算口径。
///
/// 拆出来是因为 TokenChartViews.swift 贴近 500 行 / 15360B 阈值；
/// 刻度这一块是独立职责（网格线 + 三档刻度标签 + 栏宽），柱与折线的绘制不碰它。
/// 跨文件访问故 drawScale / ticks / gutterWidth 由 private 放宽为 internal。
extension TokenBarsView {

    /// 左侧刻度 + 4 条水平网格虚线
    ///
    /// 刻度值 = 归一化基准按比例缩放（与柱高同一基准，不另算口径），数值走
    /// TokenFormatting.abbreviated（跟随设置页「数值单位」：亿 / 万 或 K / M / B）。
    /// 刻度只放左栏，不占右侧（右侧留给图例与累计说明）。
    func drawScale(scale: Int, in plot: NSRect) {
        let line = NSBezierPath()
        for fraction in [0.25, 0.5, 0.75, 1.0] as [CGFloat] {
            let y = plot.minY + fraction * plot.height
            line.move(to: NSPoint(x: plot.minX, y: y))
            line.line(to: NSPoint(x: plot.maxX, y: y))
        }
        line.lineWidth = 1
        line.setLineDash([2, 3], count: 2, phase: 0)
        TokenPaneStyle.gridLine.setStroke()
        line.stroke()

        for (fraction, value) in Self.ticks(scale: scale) {
            let text = TokenFormatting.abbreviated(Double(value)) as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: TokenPaneStyle.axisFont,
                .foregroundColor: TokenPaneStyle.tertiaryText,
            ]
            let size = text.size(withAttributes: attributes)
            // 右对齐贴着绘图区左边：刻度不压柱子，柱子也不进刻度栏；
            // 上下都夹进绘图区——极端长标签宁可挤进刻度栏，也不让左侧被裁掉半个字；
            // 顶部那一档若不夹，会越出柱区压住卡头那行「累计 / 切：对比」的说明文字（实测重叠）。
            let centered = plot.minY + fraction * plot.height - size.height / 2
            let y = min(max(plot.minY, centered), plot.maxY - size.height - 1.5)
            let x = max(bounds.minX, plot.minX - 4 - size.width)
            text.draw(at: NSPoint(x: x, y: y), withAttributes: attributes)
        }
    }

    /// 刻度位置与数值（0 / 中值 / 峰值 = 归一化基准，与柱高同一基准）
    static func ticks(scale: Int) -> [(CGFloat, Int)] {
        [(0, 0), (0.5, scale / 2), (1.0, scale)]
    }

    /// 刻度栏宽度 = 最长刻度标签宽 + 与绘图区的间隙 4pt + 1pt 余量
    static func gutterWidth(for scale: Int) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: TokenPaneStyle.axisFont]
        let widest = ticks(scale: scale)
            .map { (TokenFormatting.abbreviated(Double($0.1)) as NSString).size(withAttributes: attributes).width }
            .max() ?? 0
        return max(minScaleGutter, (widest + 5).rounded(.up))
    }
}
