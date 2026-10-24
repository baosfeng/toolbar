import AppKit

// MARK: - 图标按钮行

/// 22×22 图标按钮（刷新）—— 作为面板行参与键盘焦点遍历
final class TokenIconButtonRow: MenuPanelRow {

    init(symbolName: String) {
        super.init(height: 22)
        contentStack.spacing = 0
        if let icon = MenuPanelLabel.symbol(symbolName, pointSize: 11, color: TokenPaneStyle.secondaryText) {
            contentStack.addArrangedSubview(icon)
        }
        // 内容区左右各 4pt 内边距 + 图标 15pt → 行宽 24pt 才能同时满足
        widthAnchor.constraint(equalToConstant: 24).isActive = true
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setAccessibilityLabel("刷新 Token 统计")
    }
}

// MARK: - 坐标轴行

/// 等距坐标轴标签（00 / 06 / 12 / 18 / 23 或三个日期）
final class TokenAxisRowView: NSView {

    private let labels: [NSTextField]

    init(labels: [String], leadingInset: CGFloat = 0) {
        self.labels = labels.map { text in
            let label = MenuPanelLabel.text(text, font: TokenPaneStyle.axisFont,
                                            color: TokenPaneStyle.tertiaryText)
            label.setContentHuggingPriority(.required, for: .horizontal)
            return label
        }
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView(views: self.labels)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .equalSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: leadingInset),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 更新标签文案（数量不变时原地替换文本）
    func updateLabels(_ values: [String]) {
        for (label, value) in zip(labels, values) { label.stringValue = value }
    }
}