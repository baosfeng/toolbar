import AppKit
import NetworkMonitorCore

// MARK: - 范围分段

/// 范围分段容器 — 浅底圆角 6 + 三个 18pt 高按钮
final class BillingRangeSegmentedView: NSView {

    /// 选择回调
    var onSelect: ((BillingRange) -> Void)?

    private let stack = NSStackView()
    private var buttons: [BillingRangeButtonRow] = []

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            heightAnchor.constraint(equalToConstant: 22),
        ])

        for range in BillingRange.allCases {
            let button = BillingRangeButtonRow(title: range.title) { [weak self] in
                self?.onSelect?(range)
            }
            buttons.append(button)
            stack.addArrangedSubview(button)
        }
        setAccessibilityRole(.group)
        setAccessibilityLabel("用量时间范围")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        let fitting = stack.fittingSize
        return NSSize(width: fitting.width + 4, height: 22)
    }

    /// 键盘可达行：三个范围按钮
    var focusableRows: [MenuPanelRow] { buttons }

    /// 同步选中态
    func update(selected: BillingRange) {
        for (index, range) in BillingRange.allCases.enumerated() {
            buttons[index].setSelected(range == selected)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        MenuPanelStyle.subtleFill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        super.draw(dirtyRect)
    }
}

/// 范围按钮 — 选中态强调色文字 + 15% 浅底，可点击、可键盘聚焦
final class BillingRangeButtonRow: MenuPanelRow {

    private let titleLabel: NSTextField
    private(set) var isSelected = false

    init(title: String, onClick: (() -> Void)? = nil) {
        titleLabel = MenuPanelLabel.text(title, font: BillingPaneStyle.rangeFont,
                                         color: BillingPaneStyle.secondaryText)
        titleLabel.alignment = .center
        super.init(height: 18, onClick: onClick)
        // 行内已有 4pt 边距，spacing 置 0 才能把文字两侧留白控制在 6pt（原型 padding 0 6）
        contentStack.spacing = 0
        contentStack.addArrangedSubview(MenuPanelLabel.spacer())
        contentStack.addArrangedSubview(titleLabel)
        contentStack.addArrangedSubview(MenuPanelLabel.spacer())
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        // 固定宽度：选中态字重变化（regular → semibold）不引起分段宽度抖动
        let attributes: [NSAttributedString.Key: Any] = [.font: BillingPaneStyle.rangeSelectedFont]
        let width = ceil((title as NSString).size(withAttributes: attributes).width) + 12
        widthAnchor.constraint(equalToConstant: width).isActive = true
        setAccessibilityLabel(title)
        setAccessibilityValue(isSelected ? "已选中" : "未选中")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 更新选中态（文字色 / 字重 / 底色）
    func setSelected(_ selected: Bool) {
        guard isSelected != selected else { return }
        isSelected = selected
        titleLabel.font = selected ? BillingPaneStyle.rangeSelectedFont : BillingPaneStyle.rangeFont
        titleLabel.textColor = selected ? MenuPanelStyle.accentColor : BillingPaneStyle.secondaryText
        setAccessibilityValue(selected ? "已选中" : "未选中")
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if isSelected {
            BillingPaneStyle.accentSoft.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        }
        super.draw(dirtyRect)
    }
}
