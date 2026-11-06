import AppKit

// MARK: - 页脚状态带（两页共用语法）

/// 状态带 —— 20pt 高、圆角 6、键值对横排
///
/// 取代额度页原先「页头时间戳 + provider 状态点」的两处零散状态：两页都用一个页脚带
/// 承载「数量 / 最近刷新 / 单位 / 索引」这类口径信息。
final class PaneStateBandView: NSView {

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
            heightAnchor.constraint(equalToConstant: PaneCardStyle.stateBandHeight),
        ])
        setAccessibilityRole(.staticText)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        PaneCardStyle.bandFill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        super.draw(dirtyRect)
    }

    /// 更新键值对（值为 nil 的项跳过）
    func update(items: [(key: String, value: String?)]) {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for item in items {
            guard let value = item.value, !value.isEmpty else { continue }
            stack.addArrangedSubview(MenuPanelLabel.text(item.key, font: PaneCardStyle.metaFont,
                                                         color: PaneCardStyle.tertiaryText))
            stack.addArrangedSubview(MenuPanelLabel.text(value, font: PaneCardStyle.rowValueStrongFont,
                                                         color: PaneCardStyle.secondaryText))
            // 键值成组，组间留白由父栈 spacing 给
            let spacer = NSView()
            spacer.setContentHuggingPriority(.init(1), for: .horizontal)
            spacer.widthAnchor.constraint(equalToConstant: 0).isActive = true
            stack.addArrangedSubview(spacer)
        }
        stack.addArrangedSubview(MenuPanelLabel.spacer())
        setAccessibilityLabel(items.compactMap { item in
            item.value.map { "\(item.key) \($0)" }
        }.joined(separator: "，"))
    }
}
