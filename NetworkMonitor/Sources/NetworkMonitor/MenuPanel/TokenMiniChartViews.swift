import AppKit
import NetworkMonitorCore

// MARK: - Token 页小型图表（走势 / 迷你柱 / 命中率环 / 分布条）

/// sparkline / 面积折线（分族卡、天趋势卡、命中率走势共用）
final class TokenSparkView: NSView {

    private var values: [Double] = []
    private var fill: NSColor?
    private var stroke: NSColor = TokenPaneStyle.uncachedColor

    init(height: CGFloat,
         stroke: NSColor = TokenPaneStyle.uncachedColor,
         fill: NSColor? = nil) {
        self.stroke = stroke
        self.fill = fill
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([heightAnchor.constraint(equalToConstant: height)])
        setAccessibilityRole(.image)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func update(values: [Double], accessibility: String) {
        self.values = values
        setAccessibilityLabel(accessibility)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard values.count > 1 else { return }
        let peak = max(values.max() ?? 1, 1)
        let count = values.count
        let line = NSBezierPath()
        for index in values.indices {
            let x = bounds.minX + CGFloat(index) / CGFloat(count - 1) * bounds.width
            let y = bounds.minY + CGFloat(min(1, values[index] / peak)) * (bounds.height - 2) + 1
            if index == 0 { line.move(to: NSPoint(x: x, y: y)) } else { line.line(to: NSPoint(x: x, y: y)) }
        }
        if let fill {
            let area = line.copy() as? NSBezierPath ?? NSBezierPath()
            area.line(to: NSPoint(x: bounds.maxX, y: bounds.minY))
            area.line(to: NSPoint(x: bounds.minX, y: bounds.minY))
            area.close()
            fill.withAlphaComponent(0.55).setFill()
            area.fill()
        }
        line.lineWidth = 1.4
        line.lineJoinStyle = .round
        stroke.setStroke()
        line.stroke()
    }
}

/// 迷你柱（请求数分族卡）
final class TokenMiniBarsView: NSView {

    private var values: [Double] = []

    init(height: CGFloat) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([heightAnchor.constraint(equalToConstant: height)])
        setAccessibilityRole(.image)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func update(values: [Double], accessibility: String) {
        self.values = values
        setAccessibilityLabel(accessibility)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !values.isEmpty else { return }
        let peak = max(values.max() ?? 1, 1)
        let gap: CGFloat = 1
        let width = max(1, (bounds.width - gap * CGFloat(values.count - 1)) / CGFloat(values.count))
        for index in values.indices {
            let height = max(1, CGFloat(values[index] / peak) * bounds.height)
            let rect = NSRect(x: bounds.minX + CGFloat(index) * (width + gap),
                              y: bounds.minY,
                              width: width,
                              height: height)
            TokenPaneStyle.requestColor.withAlphaComponent(values[index] >= peak ? 1 : 0.85).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5).fill()
        }
    }
}

/// 缓存命中率环（30pt，环宽 3.4pt，中心一位小数字）
final class TokenRingView: NSView {

    private var rate: Double = 0
    private var centerText = "—"

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: TokenPaneStyle.ringSize),
            heightAnchor.constraint(equalToConstant: TokenPaneStyle.ringSize),
        ])
        setAccessibilityRole(.progressIndicator)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func update(rate: Double, text: String, accessibility: String) {
        self.rate = max(0, min(1, rate))
        centerText = text
        setAccessibilityLabel(accessibility)
        setAccessibilityValue(Int(rate * 100))
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let inset = TokenPaneStyle.ringWidth / 2 + 0.5
        let rect = bounds.insetBy(dx: inset, dy: inset)
        let background = NSBezierPath(ovalIn: rect)
        background.lineWidth = TokenPaneStyle.ringWidth
        TokenPaneStyle.trackColor.setStroke()
        background.stroke()

        defer { drawCenterText() }
        guard rate > 0 else { return }
        let foreground = NSBezierPath()
        foreground.appendArc(withCenter: NSPoint(x: bounds.midX, y: bounds.midY),
                             radius: rect.width / 2,
                             startAngle: 90,
                             endAngle: 90 - CGFloat(rate) * 360,
                             clockwise: true)
        foreground.lineWidth = TokenPaneStyle.ringWidth
        foreground.lineCapStyle = .round
        TokenPaneStyle.cacheColor.setStroke()
        foreground.stroke()
    }

    /// 环内数字用手绘居中（与 SystemRingView 同法）：
    /// 用 NSTextField 贴中心点时，cell 自带内边距 + 单行 cell 顶对齐，实测「97.5」会偏上并溢出环。
    private func drawCenterText() {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: TokenPaneStyle.ringTextFont,
            .foregroundColor: TokenPaneStyle.cacheInk,
        ]
        let size = (centerText as NSString).size(withAttributes: attributes)
        (centerText as NSString).draw(at: NSPoint(x: bounds.midX - size.width / 2,
                                                  y: bounds.midY - size.height / 2),
                                      withAttributes: attributes)
    }
}

/// 分布条（项目 / 模型占比，一次性画完所有段）
final class TokenStackBarView: NSView {

    private var shares: [Double] = []
    private var colors: [NSColor] = []

    init(height: CGFloat = TokenPaneStyle.stackBarHeight) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([heightAnchor.constraint(equalToConstant: height)])
        setAccessibilityRole(.image)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// - Parameter tip: 整条悬停文案（逐段列出「provider/model 金额 · 占比」）。
    ///
    /// 条本身只有色块、没有任何文字，图例又被 296pt 宽截断成 "deepseek-v4.1-flash…"，
    /// 悬停整条是唯一能看全「哪一段是哪个 provider 的哪个模型、多少钱、占比多少」的地方。
    /// 文案由 Core 的 `TokenDerive.stackBarTip` 拼装，视图不自行拼字符串。
    func update(shares: [Double], colors: [NSColor], accessibility: String, tip: String? = nil) {
        self.shares = shares
        self.colors = colors
        setAccessibilityLabel(accessibility)
        toolTip = (tip?.isEmpty == false) ? tip : nil
        needsDisplay = true
    }

#if DEBUG
    /// 快照自证：当前挂上去的悬停文案
    var toolTipForSnapshot: String { toolTip ?? "" }
#endif

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        TokenPaneStyle.trackColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        var offset = bounds.minX
        for (index, share) in shares.enumerated() where share > 0 {
            let width = CGFloat(share) * bounds.width
            guard width > 0.5 else { continue }
            let rect = NSRect(x: offset, y: bounds.minY, width: width, height: bounds.height)
            colors[safe: index]?.setFill()
            NSBezierPath(rect: rect).fill()
            offset += width
        }
    }
}
