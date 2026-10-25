import AppKit
import NetworkMonitorCore
import QuartzCore

// MARK: - 图标按钮行

/// 20pt 高的图标按钮行 — 可点击、可键盘聚焦；加载中图标无限旋转
final class BillingIconButtonRow: MenuPanelRow {

    private let iconView: NSImageView?

    init(symbolName: String) {
        iconView = MenuPanelLabel.symbol(symbolName, pointSize: 12, color: BillingPaneStyle.secondaryText)
        super.init(height: 20, onClick: nil)
        contentStack.spacing = 0
        if let iconView { contentStack.addArrangedSubview(iconView) }
        widthAnchor.constraint(equalToConstant: 24).isActive = true
        setAccessibilityLabel("刷新额度")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize { NSSize(width: 24, height: 20) }

    /// 开关旋转动画（0.9s 一圈，无限循环）
    func setSpinning(_ spinning: Bool) {
        guard let iconView else { return }
        iconView.wantsLayer = true
        if spinning {
            guard iconView.layer?.animation(forKey: "spin") == nil else { return }
            let animation = CABasicAnimation(keyPath: "transform.rotation.z")
            animation.fromValue = 0
            animation.toValue = Double.pi * 2
            animation.duration = 0.9
            animation.repeatCount = .infinity
            animation.isRemovedOnCompletion = false
            iconView.layer?.add(animation, forKey: "spin")
            iconView.contentTintColor = MenuPanelStyle.accentColor
        } else {
            iconView.layer?.removeAnimation(forKey: "spin")
            iconView.contentTintColor = BillingPaneStyle.secondaryText
        }
    }
}

// MARK: - 空态

/// registry 为空时的整页空态
final class BillingEmptyView: NSView {

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        if let icon = MenuPanelLabel.symbol("creditcard", pointSize: 24,
                                            color: BillingPaneStyle.tertiaryText) {
            stack.addArrangedSubview(icon)
        }
        let label = MenuPanelLabel.text("暂无计费 provider",
                                        font: NSFont.systemFont(ofSize: 12),
                                        color: BillingPaneStyle.secondaryText)
        label.alignment = .center
        stack.addArrangedSubview(label)
        // 全部停用与注册表为空共用本空态：两处都能靠这句找到恢复入口
        let hint = MenuPanelLabel.text("可在「设置 › 额度 Provider」中启用",
                                       font: NSFont.systemFont(ofSize: 10.5),
                                       color: BillingPaneStyle.tertiaryText)
        hint.alignment = .center
        stack.addArrangedSubview(hint)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 120),
        ])
        setAccessibilityRole(.group)
        setAccessibilityLabel("暂无计费 provider")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}