import AppKit

// MARK: - 大号数值（卡内 hero / 详情页 hero）

/// 大号等宽数字 + 小号单位 — 卡片里 23pt、详情页顶部 28pt 共用
///
/// 数字与单位放在**同一个富文本标签**里，而不是两个 NSTextField 相邻：
/// 两个标签各自带字形左右边距（23pt 数字约 3pt/侧、9pt 单位约 3.5pt/侧），
/// 叠上 2pt 间距后视觉缝隙实测 6–8pt，原型要求「数字与 % 紧贴」。
/// 富文本按基线拼接，缝隙只剩单位字形自带的左留白（约 1pt）。
final class SystemMetricValueView: NSView {

    private let label: NSTextField
    private let valueFont: NSFont
    private let unitFont: NSFont

    init(fontSize: CGFloat, unitFontSize: CGFloat, weight: NSFont.Weight = .bold) {
        valueFont = .monospacedDigitSystemFont(ofSize: fontSize, weight: weight)
        unitFont = .monospacedDigitSystemFont(ofSize: unitFontSize, weight: .regular)
        label = NSTextField(labelWithString: "")
        label.font = valueFont
        label.textColor = SystemPalette.foreground
        label.lineBreakMode = .byClipping
        label.maximumNumberOfLines = 1
        label.isEditable = false
        label.isSelectable = false
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .horizontal)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.topAnchor.constraint(equalTo: topAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("读数")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    // 事实行 / 卡头的 NSStackView 按第一基线对齐：把基线转发给数值标签，
    // 否则 AppKit 按「底边」对齐，标签会整体偏下（数值与标签对不齐）。
    override var firstBaselineAnchor: NSLayoutYAxisAnchor { label.firstBaselineAnchor }
    override var lastBaselineAnchor: NSLayoutYAxisAnchor { label.lastBaselineAnchor }

    /// 更新数值与单位（unit 为 nil / 空串时只剩数字）
    func update(value: String, color: NSColor, unit: String? = nil) {
        let text = NSMutableAttributedString(string: value,
                                             attributes: [.font: valueFont,
                                                          .foregroundColor: color])
        if let unit, !unit.isEmpty {
            text.append(NSAttributedString(string: unit,
                                           attributes: [.font: unitFont,
                                                        .foregroundColor: SystemPalette.meta]))
        }
        label.attributedStringValue = text
        setAccessibilityLabel(unit.map { value + $0 } ?? value)
    }

    /// 空态：数值「—」、单位隐藏、颜色降级
    func reset(color: NSColor) {
        update(value: SystemPaneFormat.placeholder, color: color, unit: nil)
    }
}
