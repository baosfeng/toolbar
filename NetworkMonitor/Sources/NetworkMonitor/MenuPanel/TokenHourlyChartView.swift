import AppKit
import NetworkMonitorCore

// MARK: - 今日 24 小时堆叠柱

/// 小时堆叠柱 —— 缓存读 / 输出 / 未缓存输入三色堆叠
///
/// 口径：`usage == nil` 表示缺省（无会话或今日尚未到该小时），留白不画 0 柱；
/// 有记录但零用量的小时在底部画 3pt 斜纹；当前小时加淡底 + 描边。
/// 「比昨日」模式叠加昨日同期幽灵柱（同样按缺省留白）。
final class TokenHourlyChartView: NSView {

    /// 左侧刻度宽 —— 9pt 等宽下 "107.8M" 约 34pt，留 5pt 间距
    private static let axisWidth: CGFloat = 40
    /// 列间距
    private static let columnGap: CGFloat = 1
    /// 24 个自然小时
    private static let hourCount = 24

    private var today: [HarnessHourlyUsage] = []
    private var yesterday: [HarnessHourlyUsage] = []
    private var currentHour = 0
    private var showsYesterday = false

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: TokenPaneStyle.hourChartHeight)
    }

    /// 更新数据（同分片的 24 槽数组，nil = 缺省）
    func update(today: [HarnessHourlyUsage],
                yesterday: [HarnessHourlyUsage],
                currentHour: Int,
                showsYesterday: Bool) {
        self.today = today
        self.yesterday = yesterday
        self.currentHour = currentHour
        self.showsYesterday = showsYesterday
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let plotWidth = bounds.width - Self.axisWidth
        guard plotWidth > 20 else { return }

        var peak = 0
        for slot in today { peak = max(peak, Self.total(slot)) }
        if showsYesterday {
            for slot in yesterday { peak = max(peak, Self.total(slot)) }
        }
        peak = max(peak, 1)

        drawAxis(peak: peak)
        TokenPaneStyle.hairline.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()

        let columnWidth = max(1, (plotWidth - Self.columnGap * CGFloat(Self.hourCount - 1)) / CGFloat(Self.hourCount))
        for hour in 0..<Self.hourCount {
            guard today.indices.contains(hour) else { continue }
            let x = Self.axisWidth + CGFloat(hour) * (columnWidth + Self.columnGap)
            let columnRect = NSRect(x: x, y: 1, width: columnWidth, height: bounds.height - 1)
            let isCurrent = hour == currentHour

            if isCurrent {
                TokenPaneStyle.currentHourWash.setFill()
                columnRect.fill()
            }

            if showsYesterday, yesterday.indices.contains(hour),
               let ghostUsage = yesterday[hour].usage {
                let ghostTotal = UsageTotal.of(ghostUsage)
                if ghostTotal > 0 {
                    let height = max(2, CGFloat(Double(ghostTotal) / Double(peak)) * (bounds.height - 8))
                    TokenPaneStyle.ghostColor.setFill()
                    NSBezierPath(roundedRect: NSRect(x: x, y: 1, width: columnWidth, height: height),
                                 xRadius: 1.5, yRadius: 1.5).fill()
                }
            }

            // 缺省小时：留白（不画 0 柱）
            guard let usage = today[hour].usage else { continue }
            let usageTotal = UsageTotal.of(usage)
            if usageTotal == 0 {
                TokenChartSupport.drawHatch(in: NSRect(x: x, y: 1, width: columnWidth, height: 3),
                                            color: TokenPaneStyle.trackColor, spacing: 2)
                continue
            }

            let stackHeight = max(3, CGFloat(Double(usageTotal) / Double(peak)) * (bounds.height - 8))
            let stackWidth = max(2, (columnWidth * 0.74).rounded())
            let stackRect = NSRect(x: x + (columnWidth - stackWidth) / 2, y: 1,
                                   width: stackWidth, height: stackHeight)
            drawStack(in: stackRect, usage: usage)

            if isCurrent {
                let outline = NSBezierPath(roundedRect: stackRect.insetBy(dx: -1, dy: -0.5),
                                           xRadius: 2.5, yRadius: 2.5)
                outline.lineWidth = 1
                TokenPaneStyle.cacheColor.setStroke()
                outline.stroke()
            }
        }
    }

    /// 左侧刻度：峰值 / 半峰 / 0
    private func drawAxis(peak: Int) {
        let rows: [(String, CGFloat)] = [
            (TokenFormat.abbreviated(peak), bounds.height - 11),
            (TokenFormat.abbreviated(peak / 2), bounds.midY - 5),
            ("0", 0),
        ]
        for (text, y) in rows {
            TokenChartSupport.draw(text, font: TokenPaneStyle.axisFont, color: TokenPaneStyle.tertiaryText,
                                   in: NSRect(x: 0, y: y, width: Self.axisWidth - 5, height: 11),
                                   alignment: .right)
        }
    }

    /// 画堆叠段：底部缓存读 → 输出 → 顶部未缓存输入，段占比极小时保底 1.5pt
    private func drawStack(in rect: NSRect, usage: HarnessTokenUsage) {
        let total = UsageTotal.of(usage)
        guard total > 0, rect.height > 0 else { return }
        let segments: [(value: Int, color: NSColor)] = [
            (usage.cacheRead, TokenPaneStyle.cacheColor),
            (usage.output, TokenPaneStyle.outputColor),
            (usage.uncachedInput, TokenPaneStyle.inputColor),
        ]
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).addClip()
        var y = rect.minY
        var remaining = rect.height
        for (index, segment) in segments.enumerated() {
            guard segment.value > 0, remaining > 0 else { continue }
            let isLast = index == segments.count - 1
            let ratio = CGFloat(Double(segment.value) / Double(total))
            let height = isLast ? remaining : min(remaining, max(1.5, rect.height * ratio))
            segment.color.setFill()
            NSRect(x: rect.minX, y: y, width: rect.width, height: height).fill()
            y += height
            remaining -= height
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// 三项合计（不含缓存写入，与 hero「三项合计」口径一致）
    private static func total(_ slot: HarnessHourlyUsage) -> Int {
        guard let usage = slot.usage else { return 0 }
        return UsageTotal.of(usage)
    }
}

/// 三项合计口径
enum UsageTotal {
    static func of(_ usage: HarnessTokenUsage) -> Int {
        usage.uncachedInput + usage.output + usage.cacheRead
    }
}