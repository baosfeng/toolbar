import AppKit
import NetworkMonitorUI

// MARK: - 空态（0 个可见 provider）

/// 额度页空态 —— 图标 + 标题 + 说明 + 主按钮
///
/// 触发条件：数据层过滤后一个可见 provider 都没有。文案按 `BillingEmptyReason` 分支
/// （注册表全空 / 全部未配置 / 全部停用），按钮文案随原因变，但动作恒定：打开设置窗并选中额度 Provider 页。
/// 改前只有文字提示、没有任何可点入口。
final class BillingEmptyView: NSView {

    /// 点主按钮
    var onConfigure: (() -> Void)?

    /// 主按钮行（键盘可达）
    let configureRow: BillingPrimaryButtonRow

    private let titleLabel = MenuPanelLabel.text("", font: PaneCardStyle.sectionTitleFont,
                                                color: PaneCardStyle.secondaryText)
    private let hintLabel = NSTextField(labelWithString: "")

    init() {
        configureRow = BillingPrimaryButtonRow(title: "去设置配置")
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.alignment = .center
        hintLabel.font = PaneCardStyle.metaFont
        hintLabel.textColor = PaneCardStyle.tertiaryText
        hintLabel.alignment = .center
        hintLabel.lineBreakMode = .byWordWrapping
        hintLabel.maximumNumberOfLines = 0
        hintLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        configureRow.onClick = { [weak self] in self?.onConfigure?() }
        configureRow.setAccessibilityIdentifier("billing-empty-cta")

        let icon = MenuPanelLabel.symbol("creditcard", pointSize: 24,
                                         color: PaneCardStyle.tertiaryText)
        var stackViews: [NSView] = []
        if let icon { stackViews.append(icon) }
        stackViews.append(contentsOf: [titleLabel, hintLabel, configureRow])

        let stack = NSStackView(views: stackViews)
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 36),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -36),
            hintLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        setAccessibilityRole(.group)
        update(reason: .unknown)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 键盘可达行
    var focusableRows: [MenuPanelRow] { [configureRow] }

    /// 按原因更新文案（按钮文案与可读名同步更新）
    func update(reason: BillingEmptyReason) {
        let copy = BillingEmptyStateLogic.copy(for: reason)
        titleLabel.stringValue = copy.title
        hintLabel.stringValue = copy.hint
        configureRow.update(title: copy.action)
        configureRow.setAccessibilityLabel(copy.action + "额度 Provider")
        setAccessibilityLabel(copy.title)
        setAccessibilityHelp(copy.hint)
    }

    override func draw(_ dirtyRect: NSRect) {
        // 空态画成一张卡：与有数据时的卡片同一底色 / 圆角
        PaneCardStyle.cardFill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: PaneCardStyle.cardRadius,
                     yRadius: PaneCardStyle.cardRadius).fill()
        super.draw(dirtyRect)
    }
}
