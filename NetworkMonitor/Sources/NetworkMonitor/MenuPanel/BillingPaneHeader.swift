import AppKit
import NetworkMonitorCore
import QuartzCore

// MARK: - 页头

/// 页头 — provider 图标 + 名称（多 provider 时可点切换）+ 上次更新时间 + 刷新按钮
///
/// 加载中时间位置显示「刷新中…」，刷新图标按 0.9s 无限旋转；请求结束自动停止。
final class BillingPageHeaderView: NSView {

    /// 点刷新
    var onRefresh: (() -> Void)?
    /// 点 provider 名称（仅多 provider 时生效）
    var onProviderTap: (() -> Void)?

    private let providerRow = BillingProviderTitleRow()
    private let timeLabel = MenuPanelLabel.text("—", font: BillingPaneStyle.stampFont,
                                                color: BillingPaneStyle.tertiaryText)
    private let refreshRow = BillingIconButtonRow(symbolName: "arrow.clockwise")

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        timeLabel.alignment = .right
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)
        refreshRow.onClick = { [weak self] in self?.onRefresh?() }

        let stack = NSStackView(views: [providerRow, MenuPanelLabel.spacer(), timeLabel, refreshRow])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 20),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 键盘可达行：刷新按钮
    var refreshButtonRow: MenuPanelRow { refreshRow }

    /// 键盘可达行：provider 切换（单 provider 时不可交互）
    var providerButtonRow: MenuPanelRow { providerRow }

    /// 更新页头
    func update(provider: BillingMonitor.ProviderDescriptor?,
                lastUpdated: Date?,
                isLoading: Bool,
                showsProviderMenu: Bool) {
        providerRow.update(provider: provider, showsChevron: showsProviderMenu)
        providerRow.onClick = showsProviderMenu ? { [weak self] in self?.onProviderTap?() } : nil

        if isLoading {
            timeLabel.stringValue = "刷新中…"
        } else {
            timeLabel.stringValue = lastUpdated.map { Self.stampFormatter.string(from: $0) } ?? "—"
        }
        refreshRow.setSpinning(isLoading)
    }

    /// 时间戳（本地时区 HH:mm）
    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

// MARK: - provider 标题行

/// provider 图标 + 名称（多 provider 时带下拉箭头，整行可点击）
final class BillingProviderTitleRow: MenuPanelRow {

    private let iconView: NSImageView?
    private let nameLabel = MenuPanelLabel.text("", font: BillingPaneStyle.providerFont, color: .labelColor)
    private let chevronView: NSImageView?

    init() {
        iconView = MenuPanelLabel.symbol("cloud", pointSize: 13, color: MenuPanelStyle.accentColor)
        chevronView = MenuPanelLabel.symbol("chevron.down", pointSize: 8, color: BillingPaneStyle.tertiaryText)
        super.init(height: 20, onClick: nil)
        contentStack.spacing = 5
        if let iconView { contentStack.addArrangedSubview(iconView) }
        contentStack.addArrangedSubview(nameLabel)
        nameLabel.setContentHuggingPriority(.required, for: .horizontal)
        nameLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        if let chevronView {
            contentStack.addArrangedSubview(chevronView)
            chevronView.isHidden = true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        let fitting = contentStack.fittingSize
        return NSSize(width: fitting.width + 8, height: 20)
    }

    /// 更新 provider 展示信息
    func update(provider: BillingMonitor.ProviderDescriptor?, showsChevron: Bool) {
        nameLabel.stringValue = provider?.displayName ?? ""
        if let provider, let iconView {
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
            iconView.image = NSImage(systemSymbolName: provider.symbolName, accessibilityDescription: nil)?
                .withSymbolConfiguration(config)
            iconView.contentTintColor = MenuPanelStyle.accentColor
        }
        chevronView?.isHidden = !showsChevron
        setAccessibilityLabel("当前计费 provider \(nameLabel.stringValue)")
        invalidateIntrinsicContentSize()
    }
}

// MARK: - 刷新图标按钮行

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
