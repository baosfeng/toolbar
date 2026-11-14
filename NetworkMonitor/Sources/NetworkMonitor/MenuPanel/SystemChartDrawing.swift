import AppKit
import NetworkMonitorUI

// MARK: - 图表共用口径

/// 单核占用 — P 核在前、E 核在后，`isPerformance` 决定柱体 / 热力格配色
struct SystemCoreUsage: Equatable {
    /// 悬停气泡 / 热力格里显示的核号（如 "P1" / "E3"）
    let label: String
    /// 利用率 0...1
    let usage: Double
    /// 是否性能核（P 核）
    let isPerformance: Bool
}

/// 堆叠条的一段 —— 自绘卡片与 `SystemStackedBarView` 共用（视图侧用 typealias 保持同名）
struct SystemBarSegment: Equatable {
    /// 分段数值（与 total 同单位）
    let value: Double
    /// 分段颜色（语义色；传 .clear 表示该段留空）
    let color: NSColor
}

/// 图表绘制共用 — 采样清洗、折线与面积路径、悬停气泡
enum SystemChartDrawing {

    /// 采样窗口（与 1 秒采样 / 60 秒窗口一致）
    static let sampleLimit = 60

    /// 清洗采样：只保留最近 `sampleLimit` 个点，非有限值归零
    static func sanitized(_ values: [Double], limit: Int = sampleLimit) -> [Double] {
        values.suffix(max(2, limit)).map { $0.isFinite ? max(0, $0) : 0 }
    }

    /// 折线路径（flipped 坐标系：y 越小越靠上）
    static func linePath(values: [Double], in rect: NSRect, maximum: Double) -> NSBezierPath {
        let path = NSBezierPath()
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        guard values.count >= 2, rect.width > 0, rect.height > 0 else { return path }
        let step = rect.width / CGFloat(values.count - 1)
        for (index, value) in values.enumerated() {
            let ratio = maximum > 0 ? min(1, max(0, value / maximum)) : 0
            let point = NSPoint(x: rect.minX + CGFloat(index) * step,
                                y: rect.minY + rect.height * CGFloat(1 - ratio))
            if index == 0 { path.move(to: point) } else { path.line(to: point) }
        }
        return path
    }

    /// 面积路径（折线 + 底边闭合）
    static func areaPath(values: [Double], in rect: NSRect, maximum: Double) -> NSBezierPath {
        let path = NSBezierPath()
        guard values.count >= 2, rect.width > 0, rect.height > 0 else { return path }
        let step = rect.width / CGFloat(values.count - 1)
        path.move(to: NSPoint(x: rect.minX, y: rect.maxY))
        for (index, value) in values.enumerated() {
            let ratio = maximum > 0 ? min(1, max(0, value / maximum)) : 0
            path.line(to: NSPoint(x: rect.minX + CGFloat(index) * step,
                                  y: rect.minY + rect.height * CGFloat(1 - ratio)))
        }
        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
        path.close()
        return path
    }

    /// 叠加带路径 — 下沿 `lower`、上沿 `upper` 闭合成带（CPU 用户态面积之上的系统态带）
    ///
    /// 两条序列必须同长：调用方负责对齐（长度不等时退化为单序列绘制，避免错位成假曲线）。
    static func bandPath(lower: [Double], upper: [Double], in rect: NSRect, maximum: Double) -> NSBezierPath {
        let path = NSBezierPath()
        guard lower.count >= 2, lower.count == upper.count, rect.width > 0, rect.height > 0 else { return path }
        let step = rect.width / CGFloat(lower.count - 1)
        func point(index: Int, value: Double) -> NSPoint {
            let ratio = maximum > 0 ? min(1, max(0, value / maximum)) : 0
            return NSPoint(x: rect.minX + CGFloat(index) * step,
                           y: rect.minY + rect.height * CGFloat(1 - ratio))
        }
        path.move(to: point(index: 0, value: upper[0]))
        for index in 1..<upper.count {
            path.line(to: point(index: index, value: upper[index]))
        }
        for index in stride(from: lower.count - 1, through: 0, by: -1) {
            path.line(to: point(index: index, value: lower[index]))
        }
        path.close()
        return path
    }

    // MARK: 组件共用绘制（AppKit 视图与自绘卡片同源）
    //
    // 首屏五卡改成整卡自绘后，图上内容（面积图 / 迷你折线 / 负载三线 / 堆叠条）
    // 仍必须与二级详情页里的同名视图逐像素一致，因此绘制只留一份：视图与卡片都调这里。

    /// 迷你折线：同族纵向渐变面积 + 折线（无数据时贴一条轨道线，避免整格空白）
    @MainActor
    static func drawSparkline(values: [Double], in rect: CGRect, lineColor: NSColor,
                              fixedMaximum: Double?, fillsArea: Bool, trackColor: NSColor) {
        guard values.count >= 2 else {
            trackColor.setFill()
            CGRect(x: rect.minX, y: rect.maxY - 1, width: rect.width, height: 1).fill()
            return
        }
        let inner = rect.insetBy(dx: 1, dy: 1)
        let maximum = max(fixedMaximum ?? values.max() ?? 0, 0.000_001)
        if fillsArea {
            let area = areaPath(values: values, in: inner, maximum: maximum)
            SystemPalette.fillVerticalGradient(area, in: inner, color: lineColor)
        }
        let line = linePath(values: values, in: inner, maximum: maximum)
        line.lineWidth = 1.5
        lineColor.setStroke()
        line.stroke()
    }

    /// 面积图：三条参考线 + 同族渐变面积 + 折线；双序列时下层为「总量 − 叠加量」的带
    @MainActor
    static func drawAreaChart(values: [Double], overlayValues: [Double], in rect: CGRect,
                              lineColor: NSColor, overlayColor: NSColor,
                              fixedMaximum: Double?, gridColor: NSColor) {
        gridColor.setFill()
        for fraction: CGFloat in [0.25, 0.5, 0.75] {
            CGRect(x: rect.minX, y: rect.minY + rect.height * fraction,
                   width: rect.width, height: 0.5).fill()
        }
        guard values.count >= 2 else { return }
        let inner = rect.insetBy(dx: 0, dy: 1)
        let isOverlay = overlayValues.count == values.count
        // 叠加模式纵轴固定 1.0（0…100%），带厚 = 真实占比；单序列自适应取峰值保形状
        let maximum = fixedMaximum ?? (isOverlay ? 1 : max(values.max() ?? 0, 0.000_001))
        if isOverlay {
            let base = zip(values, overlayValues).map { total, overlay in
                min(max(total, 0), max(0, total - max(overlay, 0)))
            }
            SystemPalette.fillVerticalGradient(
                areaPath(values: base, in: inner, maximum: maximum),
                in: inner, color: lineColor, topAlpha: 0.30, bottomAlpha: 0.03)
            overlayColor.setFill()
            bandPath(lower: base, upper: values, in: inner, maximum: maximum).fill()
        } else {
            SystemPalette.fillVerticalGradient(
                areaPath(values: values, in: inner, maximum: maximum),
                in: inner, color: lineColor)
        }
        let line = linePath(values: values, in: inner, maximum: maximum)
        line.lineWidth = 2
        lineColor.setStroke()
        line.stroke()
    }

    /// 负载三线：核数参考虚线 + 15m 细虚线 / 5m 中实线 / 1m 粗实线
    @MainActor
    static func drawLoadChart(short: [Double], medium: [Double], long: [Double],
                              coreCount: Int, axisMaximum: Double, in rect: CGRect,
                              shortColor: NSColor, mediumColor: NSColor, longColor: NSColor,
                              referenceColor: NSColor, trackColor: NSColor) {
        guard short.count >= 2 || medium.count >= 2 || long.count >= 2 else {
            // 无数据：中线一条灰线，避免整格空白被误读成渲染失败
            trackColor.setFill()
            CGRect(x: rect.minX, y: rect.midY, width: rect.width, height: 0.5).fill()
            return
        }
        let inner = rect.insetBy(dx: 1, dy: 1)
        let maximum = resolvedLoadMaximum(axisMaximum: axisMaximum,
                                          series: [short, medium, long])
        if coreCount > 0 {
            let ratio = min(1, Double(coreCount) / maximum)
            let y = inner.minY + inner.height * CGFloat(1 - ratio)
            let reference = NSBezierPath()
            reference.move(to: CGPoint(x: inner.minX, y: y))
            reference.line(to: CGPoint(x: inner.maxX, y: y))
            reference.lineWidth = 1
            reference.setLineDash([2, 3], count: 2, phase: 0)
            referenceColor.setStroke()
            reference.stroke()
        }
        drawLoadSeries(long, color: longColor, width: 1, dash: [3, 2], in: inner, maximum: maximum)
        drawLoadSeries(medium, color: mediumColor, width: 1.3, dash: [], in: inner, maximum: maximum)
        drawLoadSeries(short, color: shortColor, width: 1.6, dash: [], in: inner, maximum: maximum)
    }

    /// 负载纵轴上限：调用方给了就用，没给按三序列峰值兜底（避免 0 除法）
    static func resolvedLoadMaximum(axisMaximum: Double, series: [[Double]]) -> Double {
        if axisMaximum.isFinite, axisMaximum > 0 { return axisMaximum }
        let peak = series.flatMap { $0 }.filter { $0.isFinite }.max() ?? 0
        return max(peak, 0.000_001)
    }

    /// 单条负载序列
    private static func drawLoadSeries(_ series: [Double], color: NSColor, width: CGFloat,
                                       dash: [CGFloat], in rect: CGRect, maximum: Double) {
        guard series.count >= 2 else { return }
        let path = linePath(values: series, in: rect, maximum: maximum)
        path.lineWidth = width
        if !dash.isEmpty {
            path.setLineDash(dash, count: dash.count, phase: 0)
        }
        color.setStroke()
        path.stroke()
    }

    /// 堆叠条：轨道底 + 按 total 归一的各段（段间留缝）+ 压力态内描边
    ///
    /// 改造前这段代码在 `SystemStackedBarView.draw` 里，且裁切没做 save/restore；
    /// 抽出来给卡片复用时必须成对（否则会把后续内容一起裁掉），视觉结果不变。
    @MainActor
    static func drawStackedBar(segments: [SystemBarSegment], total: Double,
                               pressureStroke: NSColor?, gapColor: NSColor, in rect: CGRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.addPath(DrawnInk.roundedPath(rect, radius: 2))
        ctx.clip()
        SystemPalette.track.setFill()
        rect.fill()

        let visible = segments.filter { $0.value.isFinite && $0.value > 0 }
        if total > 0, total.isFinite, !visible.isEmpty {
            let widths = SystemCardLayout.segmentWidths(values: visible.map { $0.value },
                                                       total: total, width: rect.width)
            var x = rect.minX
            for (index, segment) in visible.enumerated() {
                let width = widths[index]
                segment.color.setFill()
                CGRect(x: x, y: rect.minY, width: width, height: rect.height).fill()
                // 段间缝：在边界处压一条卡底色细线（首段左侧与末段右侧不画）
                if index < visible.count - 1 {
                    gapColor.setFill()
                    CGRect(x: x + width - Self.segmentGap, y: rect.minY,
                           width: Self.segmentGap, height: rect.height).fill()
                }
                x += width
            }
        }
        if let pressureStroke {
            let inner = rect.insetBy(dx: 0.5, dy: 0.5)
            let path = NSBezierPath(roundedRect: inner, xRadius: 2, yRadius: 2)
            path.lineWidth = 1
            pressureStroke.setStroke()
            path.stroke()
        }
        ctx.restoreGState()
    }

    /// 段间缝隙宽度
    static let segmentGap: CGFloat = 0.5

    /// 压力等级 → 堆叠条描边色（正常 / 未知不描边，语义与卡头圆点一致）
    @MainActor
    static func pressureStrokeColor(_ level: SystemPressureDotView.Level) -> NSColor? {
        switch level {
        case .warning: return SystemPalette.warn
        case .critical: return SystemPalette.danger
        case .normal, .unknown: return nil
        }
    }

    /// 悬停气泡：深底 + 反色文字，横向贴边钳制（纵向由调用方给定）
    @MainActor
    static func drawTooltip(_ text: String, centerX: CGFloat, topY: CGFloat, within bounds: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: MenuPanelStyle.smallValueFont,
            .foregroundColor: NSColor.windowBackgroundColor,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let padding: CGFloat = 4
        let width = size.width + padding * 2
        let height = size.height + 2
        let x = min(max(bounds.minX, centerX - width / 2), max(bounds.minX, bounds.maxX - width))
        let y = min(max(bounds.minY, topY), max(bounds.minY, bounds.maxY - height))
        let rect = NSRect(x: x, y: y, width: width, height: height)
        MenuPanelStyle.dynamicLabel(alpha: 0.92).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
        (text as NSString).draw(at: NSPoint(x: rect.minX + padding, y: rect.minY + 1),
                                withAttributes: attributes)
    }
}
