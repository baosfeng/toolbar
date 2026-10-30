import AppKit
import NetworkMonitorCore

// MARK: - 数值口径

/// 系统页数值格式化 — 界面只显示数值与单位，口径说明一律走 `toolTip`
///
/// 进位与 Core 口径一致（内存/磁盘按 1024 进位，百分比入参 0...1）；
/// 不可得一律返回「—」，由调用方决定字号与颜色，不隐藏整块。
enum SystemPaneFormat {

    /// 不可用占位
    static let placeholder = "—"

    /// 温度警示阈值（°C）：超过转警示色
    static let hotThreshold: Double = 85

    /// 百分比（入参 0...1）— 委托 Core 展示口径（越界封顶、非有限值归 0）
    static func percent(_ value: Double?) -> String {
        guard let value else { return placeholder }
        return SystemMetricsFormatting.percentText(value)
    }

    /// 容量（字节）— Core 目前只提供速率口径，容量格式化在本层补齐（1024 进位、K 以上 1 位小数）
    static func bytes(_ value: UInt64?) -> String {
        guard let value else { return placeholder }
        return bytes(Double(value))
    }

    /// 容量（字节，Double 入口：GPU 显存等）
    static func bytes(_ value: Double) -> String {
        guard value.isFinite else { return placeholder }
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var scaled = max(0, value)
        var index = 0
        while scaled >= 1024, index < units.count - 1 {
            scaled /= 1024
            index += 1
        }
        guard index > 0 else { return String(format: "%.0f %@", scaled, units[index]) }
        return String(format: "%.1f %@", scaled, units[index])
    }

    /// 速率（字节/秒）— 委托 Core 口径（nil 与非法值都返回「—」）
    static func rate(_ value: Double?) -> String {
        SystemMetricsFormatting.byteRateText(value)
    }

    /// 每秒操作数（IOPS）— 纯数值 + 单位，nil 显示「—」（首帧无基线，不显示 0）
    static func iops(_ value: Double?) -> String {
        guard let value, value.isFinite else { return placeholder }
        return String(format: "%.0f op/s", max(0, value))
    }

    /// 容量（GB，1 位小数，不带单位）— 内存四段数值行用，单位写在卡片 toolTip
    static func gigabytes(_ value: UInt64) -> String {
        String(format: "%.1f", Double(value) / 1_073_741_824)
    }

    /// 0...1 比例原值（进度条用）；nil 或非有限值返回 0
    static func unitFraction(_ value: Double?) -> Double {
        guard let value, value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    /// 温度数值（不含度符号，单位由独立标签显示）
    static func temperatureNumber(_ celsius: Double?) -> String {
        guard let celsius, celsius.isFinite else { return placeholder }
        return String(format: "%.0f", celsius)
    }

    /// 带度符号的温度（副行使用）
    static func temperature(_ celsius: Double?) -> String {
        guard let celsius, celsius.isFinite else { return placeholder }
        return String(format: "%.0f°", celsius)
    }

    /// 功耗
    static func watt(_ value: Double?) -> String {
        guard let value, value.isFinite else { return placeholder }
        return String(format: "%.0f W", value)
    }

    /// 温度卡副行：GPU 温度 + 功耗（任一不可得都保留「—」占位）
    static func thermalDetail(gpu: Double?, power: Double?) -> String {
        "GPU \(temperature(gpu)) · \(watt(power))"
    }
}

// MARK: - 顶部三联小格

/// 顶部指标小格 — 大号等宽数字 + 12pt 迷你曲线 + ≤4 字标签
///
/// 背景用 draw 阶段解析语义色（layer 背景会固化 CGColor，深浅色切换不跟随）。
final class SystemHeroTileView: NSView {

    private let valueLabel: NSTextField
    private let sparkline: SystemSparklineView
    private let captionLabel: NSTextField

    /// 三联 → 四联后的主数值字号：四格等分后每格只有约 71pt 宽，
    /// 沿用 26pt 会在「100%」这类三位数时挤掉单位，故降到 20pt（原型 v4 约 19–21pt）。
    static let compactValueFont = NSFont.monospacedDigitSystemFont(ofSize: 20, weight: .semibold)

    // 默认值用 NSColor 自带语义色而非 MenuPanelStyle：默认参数表达式在
    // 非隔离上下文求值，直接引用 @MainActor 属性会被 Swift 6 拒绝（实测编译错误）
    init(label: String, lineColor: NSColor = .controlAccentColor, showsSparkline: Bool = true) {
        valueLabel = MenuPanelLabel.text(SystemPaneFormat.placeholder,
                                        font: Self.compactValueFont,
                                        color: MenuPanelStyle.tertiaryText)
        sparkline = SystemSparklineView(lineColor: lineColor, height: 12)
        captionLabel = MenuPanelLabel.text(label,
                                           font: MenuPanelStyle.sectionFont,
                                           color: MenuPanelStyle.tertiaryText)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        valueLabel.alignment = .center
        captionLabel.alignment = .center
        // 无曲线的格子（负载）：数值与标签直接居中，不留空轨道
        sparkline.isHidden = !showsSparkline

        let arranged: [NSView] = showsSparkline
            ? [valueLabel, sparkline, captionLabel]
            : [valueLabel, captionLabel]
        let stack = NSStackView(views: arranged)
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        if showsSparkline {
            sparkline.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        setAccessibilityRole(.group)
        setAccessibilityLabel(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        MenuPanelStyle.subtleFill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: MenuPanelStyle.cornerRadius,
                     yRadius: MenuPanelStyle.cornerRadius).fill()
        super.draw(dirtyRect)
    }

    /// 更新数值（空态传「—」并降到三级文字色）
    func update(value: String, color: NSColor = .labelColor) {
        valueLabel.stringValue = value
        valueLabel.textColor = color
    }

    /// 更新迷你曲线
    func update(history: [Double]) {
        sparkline.values = history
    }
}

// MARK: - 卡片容器

/// 卡片容器 — 标题 + 右侧补充 + 垂直内容区，圆角填充背景
///
/// 口径说明只写在 `toolTip`（界面不出现解释性文字）。
final class SystemCardView: NSView {

    /// 内容区（各卡向此追加行）
    private let contentStack = NSStackView()
    private let trailingLabel: NSTextField
    /// 卡头第三槽（图例 / 徽标等附属件），位于标题与右侧补充之间
    private let headerAccessorySlot = NSStackView()

    init(title: String, trailing: String = "") {
        trailingLabel = MenuPanelLabel.text(trailing,
                                            font: MenuPanelStyle.smallValueFont,
                                            color: MenuPanelStyle.tertiaryText)
        let titleLabel = MenuPanelLabel.section(title)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        headerAccessorySlot.orientation = .horizontal
        headerAccessorySlot.alignment = .centerY
        headerAccessorySlot.spacing = 4
        let header = NSStackView(views: [titleLabel, headerAccessorySlot,
                                         MenuPanelLabel.spacer(), trailingLabel])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 5

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 4

        let stack = NSStackView(views: [header, contentStack])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            contentStack.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        setAccessibilityRole(.group)
        setAccessibilityLabel(title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        MenuPanelStyle.subtleFill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: MenuPanelStyle.cornerRadius,
                     yRadius: MenuPanelStyle.cornerRadius).fill()
        super.draw(dirtyRect)
    }

    /// 追加一行内容（自动撑满卡片内容宽）
    func addContent(_ view: NSView) {
        contentStack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
    }

    /// 更新右侧补充文案
    func updateTrailing(_ text: String) {
        trailingLabel.stringValue = text
    }

    /// 在卡头装入附属件（图例 / 状态徽标）——与标题同行，不新增行高
    ///
    /// 位置在标题之后、弹性占位之前；重复调用替换上一件，避免同一槽位堆叠。
    func setHeaderAccessory(_ view: NSView) {
        for existing in headerAccessorySlot.arrangedSubviews {
            headerAccessorySlot.removeArrangedSubview(existing)
            existing.removeFromSuperview()
        }
        headerAccessorySlot.addArrangedSubview(view)
    }
}
