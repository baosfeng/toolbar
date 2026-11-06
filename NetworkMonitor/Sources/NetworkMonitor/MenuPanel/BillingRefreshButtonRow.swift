import AppKit
import QuartzCore

// MARK: - 页头刷新按钮行

/// 22pt 高的图标按钮行 —— 可点击、可键盘聚焦；加载中图标无限旋转
///
/// 与 Token 页 `TokenIconButtonRow` 同尺寸同字形（24×22），两页页头因此完全对齐。
final class BillingIconButtonRow: MenuPanelRow {

    private let iconView: NSImageView?

    init(symbolName: String) {
        iconView = MenuPanelLabel.symbol(symbolName, pointSize: 11,
                                         color: PaneCardStyle.secondaryText)
        super.init(height: PaneCardStyle.pageHeadHeight, onClick: nil)
        contentStack.spacing = 0
        if let iconView { contentStack.addArrangedSubview(iconView) }
        widthAnchor.constraint(equalToConstant: 24).isActive = true
        setAccessibilityLabel("刷新额度")
        setAccessibilityIdentifier("billing-refresh")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize { NSSize(width: 24, height: PaneCardStyle.pageHeadHeight) }

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
            iconView.contentTintColor = PaneCardStyle.accentText
        } else {
            iconView.layer?.removeAnimation(forKey: "spin")
            iconView.contentTintColor = PaneCardStyle.secondaryText
        }
    }
}
