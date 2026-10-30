import AppKit

// MARK: - 卡头微图例

/// 6pt 圆角色块 — 用 draw 而非 layer 背景：layer 会固化 CGColor，深浅色切换不跟随
final class SystemSwatchView: NSView {

    /// 色块颜色（动态色，draw 内按当前外观解析）
    var color: NSColor = SystemPalette.cpu {
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
/// 数值走 CPU 族 ink（原型 `--m-cpu-ink`），色块分别是 `--m-cpu` / `--m-cpu-2`。
final class SystemUsageSplitView: NSView {

    private let userLabel: NSTextField
    private let systemLabel: NSTextField

    init() {
        userLabel = MenuPanelLabel.text(SystemPaneFormat.placeholder,
                                        font: MenuPanelStyle.smallValueFont,
                                        color: SystemPalette.cpuInk)
        systemLabel = MenuPanelLabel.text(SystemPaneFormat.placeholder,
                                          font: MenuPanelStyle.smallValueFont,
                                          color: SystemPalette.cpuInk)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let userSwatch = SystemSwatchView()
        userSwatch.color = SystemPalette.cpu
        let systemSwatch = SystemSwatchView()
        systemSwatch.color = SystemPalette.cpuSecondary
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
