import AppKit

// MARK: - 坐标轴行（从 TokenRowViews.swift 拆出：单文件体积门禁）

/// 坐标轴行（等宽分列，8 / 24 个刻度都能对齐）
final class TokenAxisView: NSView {

    private let stack = NSStackView()
    private var labels: [String] = []

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .fillEqually
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 10),
        ])
        setAccessibilityRole(.staticText)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func update(labels: [String]) {
        guard labels != self.labels else { return }
        self.labels = labels
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for label in labels {
            let field = MenuPanelLabel.text(label, font: TokenPaneStyle.axisFont,
                                            color: TokenPaneStyle.tertiaryText)
            field.alignment = .center
            field.lineBreakMode = .byClipping
            stack.addArrangedSubview(field)
        }
    }
}
