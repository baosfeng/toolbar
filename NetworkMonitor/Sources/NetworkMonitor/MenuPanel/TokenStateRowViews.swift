import AppKit
import NetworkMonitorCore

// MARK: - Token 页底部状态行与口径说明（从 TokenRowViews.swift 拆出：单文件体积门禁）

/// 底状态带（峰 / 昨 / 索引 / 缓存）
final class TokenStateBandView: NSView {

    private let stack = NSStackView()

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -7),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: TokenPaneStyle.stateBandHeight),
        ])
        setAccessibilityRole(.staticText)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        TokenPaneStyle.bandFill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        super.draw(dirtyRect)
    }

    func update(items: [TokenStateItem]) {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for item in items {
            let title = MenuPanelLabel.text(item.title, font: TokenPaneStyle.stateFont,
                                            color: TokenPaneStyle.tertiaryText)
            let valueColor: NSColor
            switch item.tone {
            case .plain: valueColor = TokenPaneStyle.secondaryText
            case .accent: valueColor = TokenPaneStyle.uncachedInk
            case .cache: valueColor = TokenPaneStyle.cacheInk
            case .request: valueColor = TokenPaneStyle.requestInk
            }
            let value = MenuPanelLabel.text(item.value, font: TokenPaneStyle.stateValueFont,
                                            color: valueColor)
            let group = NSStackView(views: [title, value])
            group.orientation = .horizontal
            group.alignment = .firstBaseline
            group.spacing = 3
            stack.addArrangedSubview(group)
        }
        stack.addArrangedSubview(MenuPanelLabel.spacer())
        setAccessibilityLabel(items.map { $0.title + " " + $0.value }.joined(separator: "，"))
    }
}

/// 口径说明段（二级页底部）
final class TokenNoteView: NSView {

    private let label = MenuPanelLabel.text("", font: TokenPaneStyle.noteFont,
                                            color: TokenPaneStyle.tertiaryText)

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.topAnchor.constraint(equalTo: topAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func update(_ text: String) {
        label.stringValue = text
    }
}

extension Array {
    /// 越界安全的取下标（图表配色数组与数据长度不一致时不崩）
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
