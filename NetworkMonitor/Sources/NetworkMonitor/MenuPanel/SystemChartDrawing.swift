import AppKit

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
