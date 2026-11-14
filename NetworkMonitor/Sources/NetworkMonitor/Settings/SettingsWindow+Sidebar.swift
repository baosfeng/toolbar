import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 侧栏（拆出自 SettingsWindow.swift：窗口主文件只留容器与切页）

/// 侧栏构建 —— 窗口与 DEBUG 首开探针共用同一套结构
///
/// 为什么要抽成工厂：侧栏不再是「一条平铺列表」，而是「品牌行 + 三段分组 + 段头」，
/// 探针若自己再拼一遍，改版式时两处必有一处忘了改（探针图会误导验收）。
@MainActor
enum SettingsSidebarBuilder {

    /// 构建结果：侧栏视图（含右侧 0.5pt 竖线）+ 按分类索引的导航项
    struct Built {
        let view: NSView
        let items: [SettingsSection: SettingsSidebarItemView]
    }

    /// 构建侧栏
    /// - Parameter onSelect: 点击导航项的回调（探针传空实现）
    static func make(onSelect: @escaping (SettingsSection) -> Void) -> Built {
        let sidebar = SettingsSurfaceView { SettingsTheme.surface }
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(stack)

        var items: [SettingsSection: SettingsSidebarItemView] = [:]
        var lastView: NSView?

        // 品牌行（图标 + 应用名），与定稿一致；侧栏顶部第一行
        let brand = makeBrandRow()
        stack.addArrangedSubview(brand)
        brand.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.setCustomSpacing(SettingsTheme.sidebarGroupSpacing, after: brand)
        lastView = brand

        for group in SettingsSidebarLayout.groups {
            let header = makeGroupHeader(group.segment.title)
            if let lastView {
                stack.setCustomSpacing(SettingsTheme.sidebarGroupSpacing, after: lastView)
            }
            stack.addArrangedSubview(header)
            header.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            stack.setCustomSpacing(SettingsTheme.sidebarGroupGap, after: header)
            lastView = header

            for id in group.items {
                guard let section = SettingsSection(sidebarID: id) else { continue }
                let item = SettingsSidebarItemView(section: section)
                item.onSelect = { onSelect(section) }
                stack.addArrangedSubview(item)
                item.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
                // 组内项间距 1pt（定稿侧栏 gap:1px），最后一项也设，交给下一段段头复写
                stack.setCustomSpacing(1, after: item)
                items[section] = item
                lastView = item
            }
        }

        // 右侧 0.5pt 竖线：侧栏与内容区同为 surface，没有这条线两层分不开
        let hairline = SettingsSurfaceView { SettingsTheme.hairline }
        sidebar.addSubview(hairline)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor,
                                          constant: SettingsTheme.sidebarInset),
            stack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor,
                                            constant: -SettingsTheme.sidebarInset),
            stack.topAnchor.constraint(equalTo: sidebar.topAnchor,
                                       constant: SettingsTheme.sidebarTopInset),
            hairline.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            hairline.topAnchor.constraint(equalTo: sidebar.topAnchor),
            hairline.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor),
            hairline.widthAnchor.constraint(equalToConstant: 0.5),
        ])
        return Built(view: sidebar, items: items)
    }

    // MARK: 私有

    /// 段头 —— 10.5pt semibold 三级色，左右内缩 8pt
    private static func makeGroupHeader(_ title: String) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        let label = MenuPanelLabel.text(title, font: SettingsTheme.sidebarGroupFont,
                                        color: SettingsTheme.textTertiary)
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor,
                                           constant: SettingsTheme.sidebarInset),
            label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
            label.topAnchor.constraint(equalTo: container.topAnchor),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    /// 品牌行 —— 应用图标 18pt + 应用名 12.5pt semibold
    ///
    /// 图标取运行期应用图标（快照环境下若取不到就只留名字，不画占位方块）。
    private static func makeBrandRow() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 7
        if let icon = NSApp.applicationIconImage {
            let iconView = NSImageView()
            iconView.image = icon
            iconView.imageScaling = .scaleProportionallyDown
            iconView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                iconView.widthAnchor.constraint(equalToConstant: 18),
                iconView.heightAnchor.constraint(equalToConstant: 18),
            ])
            row.addArrangedSubview(iconView)
        }
        row.addArrangedSubview(MenuPanelLabel.text(AppIdentity.displayName,
                                                   font: SettingsTheme.brandFont,
                                                   color: SettingsTheme.textPrimary))
        row.addArrangedSubview(MenuPanelLabel.spacer())
        row.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(row)
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: SettingsTheme.brandRowHeight),
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor,
                                         constant: SettingsTheme.sidebarInset),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            row.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        return container
    }
}

// MARK: - 分类映射

extension SettingsSection {

    /// 稳定 id → 分类（侧栏按 UI 层的分组表建视图时使用）
    ///
    /// 反查走穷尽 switch：新增分类若忘了在 `SettingsSidebarLayout` 里出现，
    /// 这里仍能编译，但侧栏不会显示它——单测「九项各出现一次」会直接红。
    init?(sidebarID: SettingsSectionID) {
        switch sidebarID {
        case .general: self = .general
        case .appearance: self = .appearance
        case .providers: self = .providers
        case .clipboard: self = .clipboard
        case .capture: self = .capture
        case .transfer: self = .transfer
        case .notifications: self = .notifications
        case .system: self = .system
        case .about: self = .about
        }
    }

    /// 分类 → 稳定 id
    var sidebarID: SettingsSectionID {
        switch self {
        case .general: return .general
        case .appearance: return .appearance
        case .providers: return .providers
        case .clipboard: return .clipboard
        case .capture: return .capture
        case .transfer: return .transfer
        case .notifications: return .notifications
        case .system: return .system
        case .about: return .about
        }
    }
}

// MARK: - 侧栏导航项

/// 侧栏分类项 —— 图标 14pt + 文字 12pt，选中态 `selectedFill` 底 + `accent` 文字与图标
///
/// 不用系统 selection 蓝（那是「系统控件」的语义色，不是主题角色）：
/// 选中底色与文字色都取主题角色，换主题后整栏跟着变。
///
/// 底色画在 `draw` 里而不是写进 `layer.backgroundColor`：动态色一旦转成 CGColor
/// 就在设置那一刻被解析死，换主题（不改外观）时旧色会残留。
final class SettingsSidebarItemView: NSView {

    /// 点击回调
    var onSelect: (() -> Void)?

    /// 选中态
    var isSelected: Bool = false {
        didSet {
            guard isSelected != oldValue else { return }
            updateAppearance()
        }
    }

    private let section: SettingsSection
    private let iconView: NSImageView?
    private let titleLabel: NSTextField

    private var isHovered = false {
        didSet { updateAppearance() }
    }

    init(section: SettingsSection) {
        self.section = section
        iconView = MenuPanelLabel.symbol(section.symbolName,
                                         pointSize: SettingsTheme.sidebarIconSize,
                                         color: SettingsTheme.ghost)
        titleLabel = MenuPanelLabel.text(section.title, font: SettingsTheme.sidebarItemFont,
                                         color: SettingsTheme.textSecondary)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        if let iconView { row.addArrangedSubview(iconView) }
        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(MenuPanelLabel.spacer())
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor,
                                         constant: SettingsTheme.sidebarInset),
            row.trailingAnchor.constraint(equalTo: trailingAnchor,
                                          constant: -SettingsTheme.sidebarInset),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: SettingsTheme.sidebarItemHeight),
        ])
        setAccessibilityLabel(section.title)
        setAccessibilityRole(.button)
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeInKeyWindow],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onSelect?()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isSelected || isHovered else { return }
        SettingsTheme.selectedFill.setFill()
        NSBezierPath(roundedRect: bounds,
                     xRadius: SettingsTheme.sidebarItemRadius,
                     yRadius: SettingsTheme.sidebarItemRadius).fill()
    }

    private func updateAppearance() {
        titleLabel.font = isSelected ? SettingsTheme.sidebarItemSelectedFont
                                     : SettingsTheme.sidebarItemFont
        titleLabel.textColor = isSelected ? SettingsTheme.accent : SettingsTheme.textSecondary
        iconView?.contentTintColor = isSelected ? SettingsTheme.accent : SettingsTheme.ghost
        needsDisplay = true
    }
}
