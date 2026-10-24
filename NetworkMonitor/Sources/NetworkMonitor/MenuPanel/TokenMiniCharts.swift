import AppKit
import NetworkMonitorCore

// MARK: - 迷你图（复用率折线 / 请求数小柱）

/// 缓存复用率 sparkline —— 近 30 天按天，缺数据日断开（不插值）
final class TokenSparklineView: NSView {

    private var values: [Double?] = []

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: TokenPaneStyle.miniChartHeight)
    }

    /// 更新序列（0…1，nil = 该日无数据）
    func update(values: [Double?]) {
        self.values = values
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard bounds.width > 4, bounds.height > 4 else { return }
        let pad: CGFloat = 3
        let plotHeight = bounds.height - pad * 2
        // 纵轴按数据区间（上下各留 8% 余量）缩放：复用率长期在 98% 附近，
        // 若按 0–100% 固定绘制会压成一条平线，看不出近 30 天波动
        let present = values.compactMap { $0 }
        let lower = max(0, (present.min() ?? 0) - 0.08)
        let upper = min(1, (present.max() ?? 1) + 0.08)
        let span = max(upper - lower, 0.001)
        func point(index: Int, value: Double) -> NSPoint {
            let x = values.count <= 1 ? bounds.midX : CGFloat(index) / CGFloat(values.count - 1) * bounds.width
            let ratio = (min(max(value, lower), upper) - lower) / span
            return NSPoint(x: x, y: pad + CGFloat(ratio) * plotHeight)
        }

        // 分段规则（避免空档断线后残留填充块）：
        // - ≥3 个连续点：面积填充 + 折线
        // - 2 个点：只画折线（不填面积，否则会渲染成一块孤立色块）
        // - 1 个点：只画一个圆点（孤立的单日数据仍然可见）
        var segment: [NSPoint] = []
        func flush() {
            let points = segment
            segment.removeAll()
            guard let first = points.first else { return }
            if points.count == 1 {
                TokenPaneStyle.cacheColor.setFill()
                NSBezierPath(ovalIn: NSRect(x: first.x - 1.5, y: first.y - 1.5, width: 3, height: 3)).fill()
                return
            }
            let line = NSBezierPath()
            line.lineWidth = 1.4
            line.lineJoinStyle = .round
            line.lineCapStyle = .round
            line.move(to: first)
            for item in points.dropFirst() { line.line(to: item) }
            if points.count >= 3 {
                let area = NSBezierPath()
                area.move(to: NSPoint(x: first.x, y: pad))
                for item in points { area.line(to: item) }
                area.line(to: NSPoint(x: points[points.count - 1].x, y: pad))
                area.close()
                TokenPaneStyle.cacheColor.withAlphaComponent(0.12).setFill()
                area.fill()
            }
            TokenPaneStyle.cacheColor.setStroke()
            line.stroke()
        }
        for (index, value) in values.enumerated() {
            if let value {
                segment.append(point(index: index, value: value))
            } else {
                flush()
            }
        }
        flush()
    }
}


/// 请求数小柱 —— 今日按小时（nil = 未到 / 无数据），其它范围按天
final class TokenRequestBarsView: NSView {

    private var values: [Int?] = []

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: TokenPaneStyle.miniChartHeight)
    }

    /// 更新数值（nil = 缺省，画轨道底色）
    func update(values: [Int?]) {
        self.values = values
        needsDisplay = true
#if DEBUG
        // 自证：确认小图拿到的是 24 槽（今日按小时）而不是被压缩过的有数据小时序列
        let nonEmpty = values.enumerated().filter { $0.element != nil }.map { $0.offset }
        AppContext.shared.logger.debug("请求小图槽位：count=\(values.count)，非空下标=\(nonEmpty)")
#endif
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !values.isEmpty, bounds.width > 4 else { return }
        let peak = max(1, values.compactMap { $0 }.max() ?? 1)
        let gap: CGFloat = 1
        let width = max(1, (bounds.width - gap * CGFloat(values.count - 1)) / CGFloat(values.count))
        for (index, value) in values.enumerated() {
            let x = CGFloat(index) * (width + gap)
            // 缺省 / 零值：每个槽都画一条 1pt 淡轨道，空位也落在自己的 24 槽位置上，
            // 避免左侧看起来「没画东西」或被误读成柱子被压缩排列
            guard let value, value > 0 else {
                TokenPaneStyle.trackColor.setFill()
                NSRect(x: x, y: 0, width: width, height: 1).fill()
                continue
            }
            // 非零值保底 2pt：个位数请求量在 30pt 高的小图里也必须可见
            let height = max(2, CGFloat(Double(value) / Double(peak)) * bounds.height)
            TokenPaneStyle.outputColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: 0, width: width, height: height),
                         xRadius: 1, yRadius: 1).fill()
        }
    }
}

/// 模型分布环形图 —— Top 5 + 其它，中央显示累计口径
final class TokenDonutView: NSView {

    private var slices: [(share: Double, color: NSColor)] = []

    override var intrinsicContentSize: NSSize {
        NSSize(width: TokenPaneStyle.donutSize, height: TokenPaneStyle.donutSize)
    }

    /// 更新扇区（share 为 0…1，顺序即绘制顺序）
    func update(slices: [(share: Double, color: NSColor)]) {
        self.slices = slices
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let size = min(bounds.width, bounds.height)
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let radius = (size - TokenPaneStyle.donutRingWidth) / 2
        let ringRect = NSRect(x: center.x - radius, y: center.y - radius,
                              width: radius * 2, height: radius * 2)

        // 轨道底
        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = TokenPaneStyle.donutRingWidth
        TokenPaneStyle.trackColor.setStroke()
        track.stroke()

        var startAngle: CGFloat = 90
        for slice in slices {
            guard slice.share > 0 else { continue }
            let sweep = CGFloat(slice.share) * 360
            let arc = NSBezierPath()
            arc.appendArc(withCenter: center, radius: radius,
                          startAngle: startAngle, endAngle: startAngle - sweep, clockwise: true)
            arc.lineWidth = TokenPaneStyle.donutRingWidth
            slice.color.setStroke()
            arc.stroke()
            startAngle -= sweep
        }

        // 中央两行：天数 + 口径
        TokenChartSupport.draw("\(daysLabel)",
                               font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold),
                               color: .labelColor,
                               in: NSRect(x: bounds.midX - 30, y: bounds.midY + 1, width: 60, height: 12),
                               alignment: .center)
        TokenChartSupport.draw("累计",
                               font: NSFont.systemFont(ofSize: 8),
                               color: TokenPaneStyle.tertiaryText,
                               in: NSRect(x: bounds.midX - 30, y: bounds.midY - 11, width: 60, height: 10),
                               alignment: .center)
    }

    private var daysLabel = "30 天"

    /// 中央标签文案（口径天数）
    func setCenterTitle(_ text: String) {
        daysLabel = text
        needsDisplay = true
    }
}