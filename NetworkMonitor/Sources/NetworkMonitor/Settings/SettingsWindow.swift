import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 统一设置窗口

/// 统一设置窗口 — 左侧三段分组侧栏 + 右侧内容区（760×540，与定稿原型一致）
///
/// 职责边界：
/// - 只做容器与切换：分类列表、内容滚动区、当前页缓存策略、外观变更后的整窗重绘
/// - 不碰业务：每页由组合根注入的工厂创建（`SettingsPaneView` 子类）
/// - 外部可指定初始分类（额度页未配置时「去设置配置」直接落到额度 Provider 页）
///
/// 页面按需创建、切走即释放：设置页里的输入框都是「保存即持久化」，
/// 重建不会丢数据，反而避免多页同时观察外部状态（设备清单、权限）。
///
/// 取色：窗口底 / 侧栏底 / 内容区底全部是主题 `surface`（不再用系统语义色），
/// 侧栏右侧 0.5pt `hairline` 竖线把两层分开。
@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {

    /// 页工厂 — 由组合根提供，窗口只按分类取用
    typealias PaneFactory = () -> SettingsPaneView

    // 放宽为 internal：DEBUG 快照扩展文件（SettingsWindow+Snapshot.swift）要换挂内容视图
    let window: NSWindow
    // 放宽为 internal：DEBUG 快照扩展文件（SettingsWindow+Snapshot.swift）要用
    let factories: [SettingsSection: PaneFactory]
    private let logger: LoggingService
    // 放宽为 internal：DEBUG 快照扩展文件要重建同构容器
    let contentScroll = NSScrollView()
    let contentContainer = SettingsFlippedView()
    /// 窗口根视图 — 快照渲染会把视图借走再归还，这里保留引用以便重新挂回
    var rootView: NSView!
    private var items: [SettingsSection: SettingsSidebarItemView] = [:]
    private var currentSection: SettingsSection = .general
    var currentPane: SettingsPaneView?
    /// 外观 / 渲染档观察者（换主题后整窗必须立刻变）
    private var appearanceObserver: NSObjectProtocol?
    private var renderTierObserver: NSObjectProtocol?

    init(factories: [SettingsSection: PaneFactory],
         logger: LoggingService = AppContext.shared.logger) {
        self.factories = factories
        self.logger = logger
        window = NSWindow(contentRect: NSRect(origin: .zero, size: SettingsTheme.windowSize),
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
        observeAppearanceChanges()
    }

    // isolated deinit：注销观察者必须在主线程（通知中心的线程要求），
    // 与 PasteboardWatcher / UserActivityMonitor 同一写法
    isolated deinit {
        // 观察者注销放析构：窗口被关掉不一定立刻析构，但漏掉注销就是泄漏 + 野回调
        if let appearanceObserver {
            NotificationCenter.default.removeObserver(appearanceObserver)
        }
        if let renderTierObserver {
            NotificationCenter.default.removeObserver(renderTierObserver)
        }
    }

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
        let root = SettingsSurfaceView { SettingsTheme.surface }
        let sidebar = SettingsSidebarBuilder.make { [weak self] section in
            self?.select(section)
        }
        items = sidebar.items

        contentScroll.translatesAutoresizingMaskIntoConstraints = false
        contentScroll.drawsBackground = false
        contentScroll.hasVerticalScroller = true
        contentScroll.autohidesScrollers = true
        contentScroll.borderType = .noBorder
        contentScroll.documentView = contentContainer
        contentContainer.translatesAutoresizingMaskIntoConstraints = false

        let sidebarView = sidebar.view
        root.addSubview(sidebarView)
        root.addSubview(contentScroll)
        NSLayoutConstraint.activate([
            sidebarView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sidebarView.topAnchor.constraint(equalTo: root.topAnchor),
            sidebarView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            sidebarView.widthAnchor.constraint(equalToConstant: SettingsTheme.sidebarWidth),
            contentScroll.leadingAnchor.constraint(equalTo: sidebarView.trailingAnchor),
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
                                          constant: SettingsTheme.contentInset),
            pane.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor,
                                           constant: -SettingsTheme.contentInset),
            pane.topAnchor.constraint(equalTo: contentContainer.topAnchor,
                                      constant: SettingsTheme.contentInset),
            pane.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor,
                                         constant: -SettingsTheme.contentInset),
        ])
        pane.refresh()
    }

    // MARK: - 跟随外观 / 渲染档

    /// 订阅外观变更 —— 换主题后设置窗口必须**立刻**变，这是本轮的核心验收项
    ///
    /// 主题换的是「语义角色 → 色值」的映射，视图不会收到外观变更回调
    /// （系统外观没变），只有显式重绘才会重新解析动态色。
    private func observeAppearanceChanges() {
        let center = NotificationCenter.default
        appearanceObserver = center.addObserver(forName: AppEvents.appearanceChanged,
                                                object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.redrawEverything() }
        }
        renderTierObserver = center.addObserver(forName: AppEvents.renderTierChanged,
                                                object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.redrawEverything() }
        }
    }

    /// 递归置 `needsDisplay`：动态色在绘制期解析，重绘即换色
    ///
    /// 只置根视图不够——子视图各自缓存着自己的绘制结果；层背景（`wantsUpdateLayer`）
    /// 也会在 needsDisplay → updateLayer 时重新取色。
    private func redrawEverything() {
        guard let rootView else { return }
        rootView.needsDisplay = true
        Self.markNeedsDisplay(rootView)
    }

    private static func markNeedsDisplay(_ view: NSView) {
        for subview in view.subviews {
            subview.needsDisplay = true
            markNeedsDisplay(subview)
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidBecomeKey(_ notification: Notification) {
        currentPane?.refresh()
    }
}
