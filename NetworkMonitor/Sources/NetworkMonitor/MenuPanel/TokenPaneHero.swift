import AppKit
import NetworkMonitorCore

// MARK: - Token 页首屏 Hero（今日总消耗）

/// 首屏第一眼：当前范围的三项合计用**全界面最大字号**，右侧给较昨日同比与实时时间
///
/// 版式（两行，高度固定 `TokenPaneStyle.heroHeight`）：
/// 第一行「今日总消耗」+ 右对齐同比；第二行主数值 + 单位 + 右对齐实时时间。
/// 只有度量不参与交互（不抢键盘焦点），数值口径与四族卡同源（TokenPaneModel.hero）。
final class TokenHeroView: NSView {

    private let titleLabel = MenuPanelLabel.text("今日总消耗", font: TokenPaneStyle.heroLabelFont,
                                                 color: TokenPaneStyle.secondaryText)
    private let valueLabel = MenuPanelLabel.text("—", font: TokenPaneStyle.heroMainFont,
                                                 color: TokenPaneStyle.secondaryText)
    private let unitLabel = MenuPanelLabel.text("tok", font: TokenPaneStyle.heroMainUnitFont,
                                                color: TokenPaneStyle.tertiaryText)
    private let deltaLabel = MenuPanelLabel.text("较昨日 —", font: TokenPaneStyle.heroDeltaFont,
                                                 color: TokenPaneStyle.tertiaryText)
    private let clockLabel = MenuPanelLabel.text("", font: TokenPaneStyle.heroClockFont,
                                                 color: TokenPaneStyle.tertiaryText)

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        // 主数值与单位不可压缩：截断在这里等于丢失最重要的一条数据
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        unitLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        unitLabel.setContentHuggingPriority(.required, for: .horizontal)
        deltaLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        clockLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let headRow = NSStackView(views: [titleLabel, MenuPanelLabel.spacer(), deltaLabel])
        headRow.orientation = .horizontal
        headRow.alignment = .firstBaseline
        headRow.spacing = 6

        let valueRow = NSStackView(views: [valueLabel, unitLabel, MenuPanelLabel.spacer(), clockLabel])
        valueRow.orientation = .horizontal
        valueRow.alignment = .lastBaseline
        valueRow.spacing = 3

        let stack = NSStackView(views: [headRow, valueRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: TokenPaneStyle.cardPaddingX),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -TokenPaneStyle.cardPaddingX),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -2),
            heightAnchor.constraint(equalToConstant: TokenPaneStyle.heroHeight),
            headRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            valueRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        setAccessibilityRole(.staticText)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        TokenPaneStyle.cardFill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: TokenPaneStyle.cardRadius,
                     yRadius: TokenPaneStyle.cardRadius).fill()
        super.draw(dirtyRect)
    }

    func update(hero: TokenHero) {
        titleLabel.stringValue = hero.title
        valueLabel.stringValue = hero.value
        unitLabel.stringValue = hero.unit
        deltaLabel.stringValue = hero.delta
        deltaLabel.textColor = hero.hasDelta
            ? (hero.deltaUp ? TokenPaneStyle.warnInk : TokenPaneStyle.okInk)
            : TokenPaneStyle.tertiaryText
        clockLabel.stringValue = hero.clock
        let spoken: String = [hero.title, hero.value, hero.unit, hero.delta, hero.clock]
            .joined(separator: "，")
        setAccessibilityLabel(spoken)
    }

#if DEBUG
    /// 快照自证：Hero 各行的字号 / frame / 完整显示所需宽度
    func metricsForSnapshot(in reference: NSView) -> [(name: String, fontSize: CGFloat, frame: NSRect,
                                                       needed: CGFloat, text: String)] {
        layoutSubtreeIfNeeded()
        let items: [(String, NSTextField)] = [
            ("hero-title", titleLabel), ("hero-value", valueLabel), ("hero-unit", unitLabel),
            ("hero-delta", deltaLabel), ("hero-clock", clockLabel),
        ]
        return items.map { name, label in
            (name, label.font?.pointSize ?? 0, label.convert(label.bounds, to: reference),
             label.intrinsicContentSize.width, label.stringValue)
        }
    }
#endif
}
