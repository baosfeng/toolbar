import AppKit

// MARK: - 负载三值图例

/// 负载卡头三值 — 「1m · 5m · 15m」三枚「色块 + 数值」，与标题同行（零新增行高）
///
/// 负载不是百分比：三枚数值都按原值显示（可超过核数），口径与量程说明写在卡片 toolTip。
final class SystemLoadNumbersView: NSView {

    private let shortLabel: NSTextField
    private let mediumLabel: NSTextField
    private let longLabel: NSTextField

    init() {
        shortLabel = Self.valueLabel()
        mediumLabel = Self.valueLabel()
        longLabel = Self.valueLabel()
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView(views: [
            Self.item(color: SystemPaneStyle.loadShort, label: shortLabel),
            Self.item(color: SystemPaneStyle.loadMedium, label: mediumLabel),
            Self.item(color: SystemPaneStyle.loadLong, label: longLabel),
        ])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        setAccessibilityRole(.group)
        setAccessibilityLabel("负载 1 / 5 / 15 分钟")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 更新三值；整体不可得时三枚都显示「—」
    func update(short: Double?, medium: Double?, long: Double?) {
        shortLabel.stringValue = Self.text(short)
        mediumLabel.stringValue = Self.text(medium)
        longLabel.stringValue = Self.text(long)
    }

    /// 负载原值：1 位小数（与原型一致），非有限值显示「—」
    private static func text(_ value: Double?) -> String {
        guard let value, value.isFinite else { return SystemPaneFormat.placeholder }
        return String(format: "%.2f", max(0, value))
    }

    private static func valueLabel() -> NSTextField {
        MenuPanelLabel.text(SystemPaneFormat.placeholder,
                            font: MenuPanelStyle.smallValueFont,
                            color: SystemPalette.foregroundSecondary)
    }

    /// 单枚「2pt 线形色块 + 数值」：色块用线段而非方点，暗示对应曲线是线
    private static func item(color: NSColor, label: NSTextField) -> NSStackView {
        let swatch = SystemLineSwatchView()
        swatch.color = color
        let item = NSStackView(views: [swatch, label])
        item.orientation = .horizontal
        item.alignment = .centerY
        item.spacing = 2
        return item
    }
}

// MARK: - 线段色块

/// 7×2pt 线段色块 — 给线形曲线做图例（与方点色块区分：线形 ↔ 线）
final class SystemLineSwatchView: NSView {

    var color: NSColor = SystemPalette.loadShort {
        didSet { needsDisplay = true }
    }

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 7),
            heightAnchor.constraint(equalToConstant: 2),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 1, yRadius: 1).fill()
    }
}
