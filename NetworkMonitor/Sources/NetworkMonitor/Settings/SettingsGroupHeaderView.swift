import AppKit
import NetworkMonitorDesign

// MARK: - 可折叠的分组标题

/// 分组标题行 —— 左侧强调竖条 + 段名，右侧折叠箭头
///
/// 折叠是这一轮「页面太长、全是一屏字」的第二处解法：低频分组默认收起，
/// 展开/收起走 0.18s 的高度 + 淡入淡出，不是硬跳。
final class SettingsGroupHeaderView: NSView {

    /// 点箭头 = 折叠 / 展开本组
    var onToggle: (() -> Void)?

    private let chevron = NSImageView()
    private let contentRow: NSView
    private var isCollapsed = false

    init(title: String, trailingAccessory: NSView?) {
        let label = MenuPanelLabel.text(title, font: SettingsTheme.sectionTitleFont,
                                        color: SettingsTheme.textSecondary)
        // 段标题前一条强调竖条：整页扫读时先看到「分了段」，再读段名
        var views: [NSView] = [SettingsGroupMarker(), label]
        if let trailingAccessory {
            views.append(MenuPanelLabel.spacer())
            views.append(trailingAccessory)
        }
        contentRow = NSStackView(views: views)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        (contentRow as? NSStackView)?.orientation = .horizontal
        (contentRow as? NSStackView)?.alignment = .centerY
        (contentRow as? NSStackView)?.spacing = 6
        contentRow.translatesAutoresizingMaskIntoConstraints = false

        chevron.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)
        chevron.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
        chevron.contentTintColor = SettingsTheme.ghost
        chevron.translatesAutoresizingMaskIntoConstraints = false

        let toggle = NSButton()
        toggle.isBordered = false
        toggle.bezelStyle = .inline
        toggle.image = nil
        toggle.title = ""
        toggle.target = self
        toggle.action = #selector(toggleTapped)
        toggle.toolTip = "收起这一组"
        toggle.translatesAutoresizingMaskIntoConstraints = false

        addSubview(contentRow)
        addSubview(chevron)
        addSubview(toggle)
        NSLayoutConstraint.activate([
            contentRow.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentRow.centerYAnchor.constraint(equalTo: centerYAnchor),
            contentRow.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -6),
            chevron.widthAnchor.constraint(equalToConstant: 10),
            chevron.heightAnchor.constraint(equalToConstant: 10),
            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
            toggle.leadingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -6),
            toggle.trailingAnchor.constraint(equalTo: trailingAnchor),
            toggle.topAnchor.constraint(equalTo: topAnchor),
            toggle.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 14),
        ])
        setAccessibilityLabel(title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 当前是否收起（箭头方向随状态转 90°）
    func setCollapsed(_ collapsed: Bool) {
        guard collapsed != isCollapsed else { return }
        isCollapsed = collapsed
        chevron.image = NSImage(systemSymbolName: collapsed ? "chevron.right" : "chevron.down",
                                accessibilityDescription: nil)
        chevron.contentTintColor = collapsed ? SettingsTheme.textSecondary : SettingsTheme.ghost
    }

    @objc private func toggleTapped() {
        onToggle?()
    }
}
