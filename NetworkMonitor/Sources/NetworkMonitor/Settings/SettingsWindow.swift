import AppKit
import NetworkMonitorCore

// MARK: - 统一设置窗口

/// 统一设置窗口 — 左侧分类栏 + 右侧内容区（760×540，与原型一致）
///
/// 职责边界：
/// - 只做容器与切换：分类列表、内容滚动区、当前页缓存策略
/// - 不碰业务：每页由组合根注入的工厂创建（`SettingsPaneView` 子类）
/// - 外部可指定初始分类（额度页未配置时「去设置配置」直接落到额度 Provider 页）
///
/// 页面按需创建、切走即释放：设置页里的输入框都是「保存即持久化」，
/// 重建不会丢数据，反而避免多页同时观察外部状态（设备清单、权限）。
@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {

    /// 页工厂 — 由组合根提供，窗口只按分类取用
    typealias PaneFactory = () -> SettingsPaneView

    private let window: NSWindow
    private let factories: [SettingsSection: PaneFactory]
    private let logger: LoggingService
    private let sidebarStack = NSStackView()
    private let contentScroll = NSScrollView()
    private let contentContainer = SettingsFlippedView()
    /// 窗口根视图 — 快照渲染会把视图借走再归还，这里保留引用以便重新挂回
    private var rootView: NSView!
    private var items: [SettingsSection: SettingsSidebarItemView] = [:]
    private var currentSection: SettingsSection = .general
    private var currentPane: SettingsPaneView?

    init(factories: [SettingsSection: PaneFactory],
         logger: LoggingService = AppContext.shared.logger) {
        self.factories = factories
        self.logger = logger
        window = NSWindow(contentRect: NSRect(origin: .zero, size: SettingsStyle.windowSize),
                          styleMask: [.titled, .closable, .miniaturizable],
                          backing: .buffered, defer: false)
        super.init()
        window.title = "设置"
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 720, height: 460)
        window.delegate = self
        rootView = makeContentView()
        window.contentView = rootView
        window.center()
        select(.general)
    }

#if DEBUG
    /// 快照自证（仅 DEBUG）：切到指定分类并返回内容视图，供离屏渲染
    func prepareForSnapshot(_ section: SettingsSection) -> NSView? {
        // 上一次渲染把根视图借进了离屏容器并移除，这里先挂回去再切页
        window.contentView = rootView
        select(section)
        rootView.layoutSubtreeIfNeeded()
        // 内容超过一屏时上次的滚动位置会残留，快照前统一回到顶部
        contentScroll.contentView.scroll(to: .zero)
        contentScroll.reflectScrolledClipView(contentScroll.contentView)
        return rootView
    }
#endif

    // MARK: - 对外入口

    /// 打开窗口并可指定分类
    func show(section: SettingsSection? = nil) {
        if let section { select(section) } else { currentPane?.refresh() }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 关闭窗口
    func close() {
        window.close()
    }

    // MARK: - 布局

    private func makeContentView() -> NSView {
        let root = SettingsSurfaceView { SettingsStyle.pageBackground }

        sidebarStack.orientation = .vertical
        sidebarStack.alignment = .leading
        sidebarStack.spacing = 2
        sidebarStack.translatesAutoresizingMaskIntoConstraints = false

        for section in SettingsSection.allCases {
            let item = SettingsSidebarItemView(section: section)
            item.onSelect = { [weak self] in self?.select(section) }
            sidebarStack.addArrangedSubview(item)
            item.widthAnchor.constraint(equalTo: sidebarStack.widthAnchor).isActive = true
            items[section] = item
        }

        let sidebar = SettingsSurfaceView { .underPageBackgroundColor }
        sidebar.addSubview(sidebarStack)
        NSLayoutConstraint.activate([
            sidebarStack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 8),
            sidebarStack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -8),
            sidebarStack.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 12),
        ])

        contentScroll.translatesAutoresizingMaskIntoConstraints = false
        contentScroll.drawsBackground = false
        contentScroll.hasVerticalScroller = true
        contentScroll.autohidesScrollers = true
        contentScroll.borderType = .noBorder
        contentScroll.documentView = contentContainer
        contentContainer.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(sidebar)
        root.addSubview(contentScroll)
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: root.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: SettingsStyle.sidebarWidth),
            contentScroll.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            contentScroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            contentScroll.topAnchor.constraint(equalTo: root.topAnchor),
            contentScroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            contentContainer.widthAnchor.constraint(equalTo: contentScroll.contentView.widthAnchor),
            contentContainer.heightAnchor.constraint(
                greaterThanOrEqualTo: contentScroll.contentView.heightAnchor),
        ])
        return root
    }

    // MARK: - 切页

    /// 切到指定分类（重建该页并刷新）
    func select(_ section: SettingsSection) {
        guard factories[section] != nil else {
            logger.warning("设置页缺少工厂：\(section)")
            return
        }
        currentSection = section
        for (itemSection, item) in items {
            item.isSelected = (itemSection == section)
        }
        guard let pane = factories[section]?() else { return }
        currentPane?.removeFromSuperview()
        currentPane = pane
        pane.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.subviews.forEach { $0.removeFromSuperview() }
        contentContainer.addSubview(pane)
        NSLayoutConstraint.activate([
            pane.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor,
                                          constant: SettingsStyle.contentInset),
            pane.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor,
                                           constant: -SettingsStyle.contentInset),
            pane.topAnchor.constraint(equalTo: contentContainer.topAnchor,
                                      constant: SettingsStyle.contentInset),
            pane.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor,
                                         constant: -SettingsStyle.contentInset),
        ])
        pane.refresh()
    }

    // MARK: - NSWindowDelegate

    func windowDidBecomeKey(_ notification: Notification) {
        currentPane?.refresh()
    }
}

// MARK: - 侧栏项

/// 侧栏分类项 — 图标 + 文字，选中态为浅强调底 + 强调色文字（原型定稿规则）
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

    private let iconView: NSImageView?
    private let titleLabel: NSTextField
    private let section: SettingsSection
    private var isHovered = false {
        didSet { updateAppearance() }
    }

    init(section: SettingsSection) {
        self.section = section
        iconView = MenuPanelLabel.symbol(section.symbolName, pointSize: 13, color: .secondaryLabelColor)
        titleLabel = MenuPanelLabel.text(section.title, font: .systemFont(ofSize: 12.5),
                                         color: .labelColor)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 6

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
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 30),
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

    private func updateAppearance() {
        if isSelected {
            layer?.backgroundColor = SettingsStyle.accent.withAlphaComponent(0.14).cgColor
            titleLabel.textColor = SettingsStyle.accent
            iconView?.contentTintColor = SettingsStyle.accent
        } else {
            layer?.backgroundColor = isHovered
                ? NSColor.labelColor.withAlphaComponent(0.06).cgColor
                : NSColor.clear.cgColor
            titleLabel.textColor = .labelColor
            iconView?.contentTintColor = .secondaryLabelColor
        }
    }
}