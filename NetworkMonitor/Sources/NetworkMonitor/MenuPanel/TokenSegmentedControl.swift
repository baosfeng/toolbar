import AppKit

// MARK: - 小型分段控件

/// 分段控件 —— 页面范围（今日 / 近 7 天 / 近 30 天）、小时对比、趋势形态三处共用
///
/// 每段是一个 `MenuPanelRow`，因此能被面板的键盘焦点遍历命中（Tab / ↑↓ 移动、Enter 触发）。
final class TokenSegmentedControl: NSView {

    /// 选中项变化（参数：下标）
    var onSelect: ((Int) -> Void)?

    private(set) var selectedIndex = 0
    private var rows: [TokenSegmentRow] = []

    /// 键盘可达分段
    var focusableRows: [MenuPanelRow] { rows }

    init(titles: [String]) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
        ])
        for (index, title) in titles.enumerated() {
            let row = TokenSegmentRow(title: title)
            row.onClick = { [weak self] in self?.select(index, notify: true) }
            stack.addArrangedSubview(row)
            rows.append(row)
        }
        select(0, notify: false)
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        TokenPaneStyle.cardFill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
    }

    /// 选中指定分段（notify = false 时不回调，用于外部同步）
    func select(_ index: Int, notify: Bool) {
        guard rows.indices.contains(index) else { return }
        selectedIndex = index
        for (rowIndex, row) in rows.enumerated() {
            row.setSelected(rowIndex == index)
        }
        if notify { onSelect?(index) }
    }
}

/// 单个分段（选中态浅底 + 半粗文字）
final class TokenSegmentRow: MenuPanelRow {

    private let label: NSTextField
    private var selected = false

    init(title: String) {
        label = MenuPanelLabel.text(title, font: TokenPaneStyle.segmentFont,
                                    color: TokenPaneStyle.secondaryText)
        super.init(height: 16)
        contentStack.spacing = 0
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        contentStack.addArrangedSubview(label)
    }

    override var isInteractive: Bool { true }

    /// 设置选中态
    func setSelected(_ value: Bool) {
        guard selected != value else { return }
        selected = value
        label.font = value ? TokenPaneStyle.segmentSelectedFont : TokenPaneStyle.segmentFont
        label.textColor = value ? .labelColor : TokenPaneStyle.secondaryText
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if selected {
            TokenPaneStyle.selectedFill.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4).fill()
        }
        super.draw(dirtyRect)
    }
}
