import AppKit

// MARK: - 卡头微图例

/// 6pt 圆角色块 — 用 draw 而非 layer 背景：layer 会固化 CGColor，深浅色切换不跟随
final class SystemSwatchView: NSView {

    /// 色块颜色（动态色，draw 内按当前外观解析）
    var color: NSColor = MenuPanelStyle.accentColor {
        didSet { needsDisplay = true }
    }

    init(size: CGFloat = 6) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size),
            heightAnchor.constraint(equalToConstant: size),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 1.5, yRadius: 1.5).fill()
    }
}

// MARK: - CPU 用户态 / 系统态图例

/// CPU 卡头图例 — 「色块 + 数值」两枚，压在标题同一行（零新增行高）
///
/// 界面只留数值：用户态 / 系统态各自的 ticks 占比口径写在 CPU 卡 toolTip 里。
final class SystemUsageSplitView: NSView {

    private let userLabel: NSTextField
    private let systemLabel: NSTextField

    init() {
        userLabel = MenuPanelLabel.text(SystemPaneFormat.placeholder,
                                        font: MenuPanelStyle.smallValueFont,
                                        color: MenuPanelStyle.secondaryText)
        systemLabel = MenuPanelLabel.text(SystemPaneFormat.placeholder,
                                          font: MenuPanelStyle.smallValueFont,
                                          color: MenuPanelStyle.secondaryText)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let userSwatch = SystemSwatchView()
        userSwatch.color = MenuPanelStyle.accentColor
        let systemSwatch = SystemSwatchView()
        systemSwatch.color = SystemPaneStyle.systemUsageBand
        let stack = NSStackView(views: [Self.item(swatch: userSwatch, label: userLabel),
                                        Self.item(swatch: systemSwatch, label: systemLabel)])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        setAccessibilityRole(.group)
        setAccessibilityLabel("CPU 用户态与系统态")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 更新两段数值 — 取整后必须凑得出总量
    ///
    /// 传 `total` 而不是单独的 user：两段各自四舍五入会凑不出总量
    /// （total 29%、sys 14.5% → 用户 15% + 系统 15% = 30% ≠ 29%），
    /// 于是用户态按「总量取整 − 系统态取整」反算，两枚数字与卡头 hero 恒自洽。
    func update(total: Double?, system: Double?) {
        guard let total, let system else {
            userLabel.stringValue = SystemPaneFormat.placeholder
            systemLabel.stringValue = SystemPaneFormat.placeholder
            return
        }
        let totalPercent = Int((SystemPaneView.clamp(total) * 100).rounded())
        let systemPercent = min(totalPercent, Int((SystemPaneView.clamp(system) * 100).rounded()))
        systemLabel.stringValue = "\(systemPercent)%"
        userLabel.stringValue = "\(max(0, totalPercent - systemPercent))%"
    }

    /// 单枚图例：色块 + 数值（间距 2pt，与原型一致）
    private static func item(swatch: NSView, label: NSTextField) -> NSStackView {
        let item = NSStackView(views: [swatch, label])
        item.orientation = .horizontal
        item.alignment = .centerY
        item.spacing = 2
        return item
    }
}

// MARK: - 内存四段数值行

/// 内存四段数值行 — 「3.6 内核 · 6.4 活跃 · 1.2 压缩 · 4.8 空闲」+ 右侧换出量
///
/// 四段数值单位为十进制 GB（与卡头 hero 同一进位，不重复写单位，单位写在卡 toolTip）；
/// 标签均 ≤4 字，各段口径见内存卡 toolTip。
final class SystemMemorySplitView: NSView {

    private let wiredValue: NSTextField
    private let activeValue: NSTextField
    private let compressedValue: NSTextField
    private let freeValue: NSTextField
    private let swapValue: NSTextField

    init() {
        wiredValue = Self.valueLabel()
        activeValue = Self.valueLabel()
        compressedValue = Self.valueLabel()
        freeValue = Self.valueLabel()
        swapValue = Self.valueLabel()
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView(views: [
            Self.segment(value: wiredValue, caption: "内核"),
            Self.segment(value: activeValue, caption: "活跃"),
            Self.segment(value: compressedValue, caption: "压缩"),
            Self.segment(value: freeValue, caption: "空闲"),
            MenuPanelLabel.spacer(),
            Self.segment(value: swapValue, caption: "交换"),
        ])
        stack.orientation = .horizontal
        stack.alignment = .firstBaseline
        stack.spacing = 7
        stack.distribution = .gravityAreas
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        setAccessibilityRole(.group)
        setAccessibilityLabel("内存四段与换出量")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 更新四段（字节）与换出量（字节，nil 显示「—」）
    func update(wired: UInt64, active: UInt64, compressed: UInt64, free: UInt64, swapUsed: UInt64?) {
        wiredValue.stringValue = SystemPaneFormat.gigabytes(wired)
        activeValue.stringValue = SystemPaneFormat.gigabytes(active)
        compressedValue.stringValue = SystemPaneFormat.gigabytes(compressed)
        freeValue.stringValue = SystemPaneFormat.gigabytes(free)
        // 换出量量级跨 MB / GB，保留单位以免与四段的 GB 口径混淆
        swapValue.stringValue = swapUsed.map { SystemPaneFormat.bytes($0) } ?? SystemPaneFormat.placeholder
        invalidateIntrinsicContentSize()
    }

    /// 置空：四段与换出量全部显示「—」
    ///
    /// 空态不能填 0 —— 「0.0 内核」会被读成「真的只用了 0 GB」，而不是「读不到」。
    func reset() {
        for label in [wiredValue, activeValue, compressedValue, freeValue, swapValue] {
            label.stringValue = SystemPaneFormat.placeholder
        }
    }

    /// 单段数值标签（9pt 等宽数字 + 次要色）
    private static func valueLabel() -> NSTextField {
        MenuPanelLabel.text(SystemPaneFormat.placeholder,
                            font: MenuPanelStyle.smallValueFont,
                            color: MenuPanelStyle.secondaryText)
    }

    /// 单段「数值 + ≤2 字标签」（标签在后，与原型一致）
    private static func segment(value: NSTextField, caption: String) -> NSStackView {
        let captionLabel = MenuPanelLabel.text(caption,
                                               font: SystemPaneStyle.microFont,
                                               color: MenuPanelStyle.tertiaryText)
        let segment = NSStackView(views: [value, captionLabel])
        segment.orientation = .horizontal
        segment.alignment = .firstBaseline
        segment.spacing = 1.5
        return segment
    }
}
