import AppKit
import NetworkMonitorCore

// MARK: - Token 页小型图表（走势 / 迷你柱 / 命中率环 / 分布条）

/// sparkline / 面积折线（分族卡、天趋势卡、命中率走势共用）
///
/// 支持缺口：nil = 该桶没有数据（无会话的小时 / 天）。缺口处**断开**——
/// 不连线段、不落到底部 0 位置，也不参与纵轴范围计算（范围由调用方按真实值给）。
final class TokenSparkView: NSView {

    /// 序列：nil = 空缺桶（图上断开）
    private var points: [Double?] = []
    private var fill: NSColor?
    private var stroke: NSColor = TokenPaneStyle.uncachedColor
    /// 纵轴地板：默认 0（从零起画）。命中率走势在窄窗口里都是 96%–99%，
    /// 从 0 起画会整片填实成一块色块，看不出峰谷，所以允许把地板抬到序列最小值。
    private var baseline: Double = 0

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

    /// 连续序列（每天都/每桶都有数据的情形，如天趋势）
    /// - Parameter baseline: 纵轴地板（默认 0）；调用方抬高地板时须在卡头写明起点，不能悄悄拉伸
    func update(values: [Double], accessibility: String, baseline: Double = 0) {
        update(points: values.map { Optional($0) }, accessibility: accessibility, baseline: baseline)
    }

    /// 带缺口的序列：nil 段断开不画（命中率走势的空缺小时走这一条）
    func update(points: [Double?], accessibility: String, baseline: Double = 0) {
        self.points = points
        self.baseline = baseline
        setAccessibilityLabel(accessibility)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let count = points.count
        guard count > 0 else { return }
        let valid = points.compactMap { $0 }
        guard let peak = valid.max(), peak > 0 else { return }
        // 地板必须严格低于峰值（相等会除零、整条贴顶），且不能为负
        let floor = min(max(0, baseline), max(0, peak - 0.01))
        let span = max(peak - floor, 0.0001)

        func position(_ index: Int) -> NSPoint? {
            guard let value = points[index] else { return nil }
            // x 按桶序均分：缺口也占一格，数据点位置与横轴刻度对齐
            let x = count == 1
                ? bounds.midX
                : bounds.minX + CGFloat(index) / CGFloat(count - 1) * bounds.width
            let ratio = min(1, max(0, (value - floor) / span))
            return NSPoint(x: x, y: bounds.minY + CGFloat(ratio) * (bounds.height - 2) + 1)
        }

        var run: [NSPoint] = []
        func flushRun() {
            defer { run.removeAll() }
            guard let first = run.first else { return }
            if run.count == 1 {
                // 孤立有效点（两侧都是缺口）：不画线段就看不见，给一个 2.8pt 圆点
                let dot = NSBezierPath(ovalIn: NSRect(x: first.x - 1.4, y: first.y - 1.4,
                                                      width: 2.8, height: 2.8))
                stroke.setFill()
                dot.fill()
                return
            }
            let line = NSBezierPath()
            line.move(to: first)
            for point in run.dropFirst() { line.line(to: point) }
            if let fill {
                // 面积只填这一段，不把缺口也填成 0（改前整片实心到 0 就是「掉到底」的来源）
                let area = line.copy() as? NSBezierPath ?? NSBezierPath()
                let last = run[run.count - 1]
                area.line(to: NSPoint(x: last.x, y: bounds.minY))
                area.line(to: NSPoint(x: first.x, y: bounds.minY))
                area.close()
                fill.withAlphaComponent(0.55).setFill()
                area.fill()
            }
            line.lineWidth = 1.4
            line.lineJoinStyle = .round
            stroke.setStroke()
            line.stroke()
        }

        for index in 0..<count {
            if let point = position(index) { run.append(point) } else { flushRun() }
        }
        flushRun()
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

/// 缓存命中率环（默认 34pt 小环，中心一位小数字）
///
/// 外径与环宽可调：缓存屏用 72pt 大环（同一份 rate / 中心文案，不另写一个环视图）。
final class TokenRingView: NSView {

    private var rate: Double = 0
    private var centerText = "—"
    /// 环宽（默认取 TokenPaneStyle.ringWidth）
    private let ringWidth: CGFloat

    init(size: CGFloat = TokenPaneStyle.ringSize, lineWidth: CGFloat = TokenPaneStyle.ringWidth) {
        ringWidth = lineWidth
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size),
            heightAnchor.constraint(equalToConstant: size),
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
        let inset = ringWidth / 2 + 0.5
        let rect = bounds.insetBy(dx: inset, dy: inset)
        let background = NSBezierPath(ovalIn: rect)
        background.lineWidth = ringWidth
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
        foreground.lineWidth = ringWidth
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
