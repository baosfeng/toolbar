import AppKit
import NetworkMonitorCore

// MARK: - 数值口径

/// 系统页数值格式化 — 界面只显示数值与单位，口径说明一律走 `toolTip`
///
/// 进位与 Core 口径一致（内存/磁盘按 1024 进位，百分比入参 0...1）；
/// 不可得一律返回「—」，由调用方决定字号与颜色，不隐藏整块。
/// 容量与详情页格式化统一委托 `SystemDetailFormatting`，避免两处各写一套进位。
enum SystemPaneFormat {

    /// 不可用占位
    static let placeholder = SystemDetailFormatting.placeholder

    /// 温度警示阈值（°C）：超过转警示色
    static let hotThreshold: Double = 85

    /// 百分比（入参 0...1）— 委托 Core 展示口径（越界封顶、非有限值归 0）
    static func percent(_ value: Double?) -> String {
        guard let value else { return placeholder }
        return SystemMetricsFormatting.percentText(value)
    }

    /// 容量（字节）
    static func bytes(_ value: UInt64?) -> String {
        SystemDetailFormatting.byteCountText(value)
    }

    /// 容量（字节，Double 入口：GPU 显存等）
    static func bytes(_ value: Double) -> String {
        SystemDetailFormatting.byteCountText(value)
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
        SystemDetailFormatting.gigabyteValueText(value)
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

// MARK: - 顶部四联小格

/// 顶部指标小格 — 大号等宽数字 + 12pt 迷你曲线 + ≤4 字标签
///
/// 背景用 draw 阶段解析语义色（layer 背景会固化 CGColor，深浅色切换不跟随）。
final class SystemHeroTileView: NSView {

    private let valueLabel: NSTextField
    private let sparkline: SystemSparklineView
    private let captionLabel: NSTextField

    /// 底（原型 `--surface`；四联小格不是卡片 wash）
    var tileColor: NSColor = SystemPalette.surface {
        didSet { needsDisplay = true }
    }

    /// 三联 → 四联后的主数值字号：四格等分后每格只有约 71pt 宽，
    /// 沿用 26pt 会在「100%」这类三位数时挤掉单位，故降到 20pt（原型 v4 约 19–21pt）。
    static let compactValueFont = NSFont.monospacedDigitSystemFont(ofSize: 20, weight: .semibold)

    // 默认值用 NSColor 自带语义色而非 @MainActor 色板：默认参数表达式在
    // 非隔离上下文求值，直接引用 SystemPalette 属性会被 Swift 6 拒绝（实测编译错误）
    init(label: String, lineColor: NSColor = .controlAccentColor, showsSparkline: Bool = true) {
        valueLabel = MenuPanelLabel.text(SystemPaneFormat.placeholder,
                                        font: Self.compactValueFont,
                                        color: MenuPanelStyle.tertiaryText)
        sparkline = SystemSparklineView(lineColor: lineColor, height: 12)
        captionLabel = MenuPanelLabel.text(label,
                                           font: MenuPanelStyle.sectionFont,
                                           color: SystemPalette.meta)
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
        tileColor.setFill()
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

/// 卡片容器 — 语义 wash 底 + 标题 + 右侧补充 + 垂直内容区
///
/// 口径说明只写在 `toolTip`（界面不出现解释性文字）。
/// 可分族上色：`wash` 传对应族的卡底 token；不传则保持旧行为（`MenuPanelStyle.subtleFill`），
/// 其它调用点零改动。`onTap` 非空时整卡可点（进二级详情页），右侧可挂「›」入口提示。
final class SystemCardView: NSView {

    /// 内容区（各卡向此追加行）
    private let contentStack = NSStackView()
    private let trailingLabel: NSTextField
    /// 卡头第三槽（图例 / 徽标等附属件），位于标题与右侧补充之间
    private let headerAccessorySlot = NSStackView()
    /// 卡头最右槽（「›」入口提示 / 「全部 ›」按钮）
    private let headerTrailingSlot = NSStackView()
    private let washColor: NSColor
    private let chevronLabel: NSTextField

    /// 整卡点击回调（nil = 不可点）
    var onTap: (() -> Void)? {
        didSet {
            window?.invalidateCursorRects(for: self)
            setAccessibilityRole(onTap == nil ? .group : .button)
        }
    }

    /// 键盘焦点态（由面板根视图设置；决定是否画焦点环）
    private(set) var isCardKeyboardFocused = false

    init(title: String, trailing: String = "", wash: NSColor? = nil) {
        trailingLabel = MenuPanelLabel.text(trailing,
                                            font: MenuPanelStyle.smallValueFont,
                                            color: SystemPalette.meta)
        chevronLabel = MenuPanelLabel.text("›",
                                           font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                                           color: SystemPalette.meta)
        washColor = wash ?? MenuPanelStyle.subtleFill
        let titleLabel = MenuPanelLabel.text(title,
                                             font: MenuPanelStyle.sectionFont,
                                             color: SystemPalette.foregroundSecondary)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        chevronLabel.isHidden = true
        headerAccessorySlot.orientation = .horizontal
        headerAccessorySlot.alignment = .centerY
        headerAccessorySlot.spacing = 4
        headerTrailingSlot.orientation = .horizontal
        headerTrailingSlot.alignment = .centerY
        headerTrailingSlot.spacing = 2
        headerTrailingSlot.addArrangedSubview(chevronLabel)

        let header = NSStackView(views: [titleLabel, headerAccessorySlot,
                                         MenuPanelLabel.spacer(), trailingLabel,
                                         headerTrailingSlot])
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
        let shape = NSBezierPath(roundedRect: bounds, xRadius: MenuPanelStyle.cornerRadius,
                                 yRadius: MenuPanelStyle.cornerRadius)
        washColor.setFill()
        shape.fill()
        if isCardKeyboardFocused {
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1),
                                    xRadius: MenuPanelStyle.cornerRadius - 1,
                                    yRadius: MenuPanelStyle.cornerRadius - 1)
            ring.lineWidth = 2
            SystemPalette.cpu.withAlphaComponent(0.5).setStroke()
            ring.stroke()
        }
        super.draw(dirtyRect)
    }

    /// 设置键盘焦点（面板根视图驱动）
    func setCardKeyboardFocused(_ focused: Bool) {
        guard isCardKeyboardFocused != focused else { return }
        isCardKeyboardFocused = focused
        needsDisplay = true
    }

    /// 执行点击动作（Return / Space 与鼠标共用）
    func activateCard() {
        onTap?()
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
        replaceArrangedSubviews(in: headerAccessorySlot, with: [view])
    }

    /// 在卡头最右槽放入控件（「全部 ›」按钮等）——位于右侧补充文案之后
    func setHeaderAction(_ view: NSView) {
        replaceArrangedSubviews(in: headerTrailingSlot, with: [view, chevronLabel])
    }

    /// 显示 / 隐藏「›」入口提示（颜色随族 ink）
    func setDisclosure(visible: Bool, color: NSColor? = nil) {
        chevronLabel.isHidden = !visible
        if let color {
            chevronLabel.textColor = color
        }
    }

    /// 替换槽内全部视图（内部小工具）
    private func replaceArrangedSubviews(in stack: NSStackView, with views: [NSView]) {
        for existing in stack.arrangedSubviews {
            stack.removeArrangedSubview(existing)
        }
        for view in views {
            stack.addArrangedSubview(view)
        }
    }

    // MARK: 点击

    override func mouseDown(with event: NSEvent) {
        guard let onTap else {
            super.mouseDown(with: event)
            return
        }
        onTap()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if onTap != nil {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }

    override func accessibilityPerformPress() -> Bool {
        guard let onTap else { return false }
        onTap()
        return true
    }
}

// MARK: - 键盘焦点协议一致性

extension SystemCardView: MenuPanelCardFocusable {}
