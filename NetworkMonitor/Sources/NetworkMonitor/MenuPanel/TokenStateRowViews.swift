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

/// 口径说明段（二级页底部 / 缓存屏页脚 / 排行屏卡底）
///
/// - Parameter maxLines: 0 = 不限行数（二级页 / 缓存屏页脚）；N > 0 = 最多 N 行、尾部省略，
///   完整文案挂到悬停与读屏（排行屏卡底要给 3 行：全展开会把 4 行压到 35pt，单行又太省）。
final class TokenNoteView: NSView {

    private let label = MenuPanelLabel.text("", font: TokenPaneStyle.noteFont,
                                            color: TokenPaneStyle.tertiaryText)
    private let truncated: Bool

    init(maxLines: Int = 0) {
        truncated = maxLines > 0
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        // 多行必须走 byWordWrapping：byTruncatingTail 会让 field 只算一行高（实测只剩一行）
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = max(maxLines, 0)
        label.usesSingleLineMode = maxLines == 1
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
        // 限行时正文会被省略，完整口径靠悬停与读屏补全
        if truncated {
            label.toolTip = text
            setAccessibilityLabel(text)
        }
    }
}

extension Array {
    /// 越界安全的取下标（图表配色数组与数据长度不一致时不崩）
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
