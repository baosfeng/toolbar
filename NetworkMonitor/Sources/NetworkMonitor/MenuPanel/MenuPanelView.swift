import AppKit
import NetworkMonitorCore

// MARK: - 面板根视图代理

/// 面板根视图事件回调
@MainActor
protocol MenuPanelViewDelegate: AnyObject {
    /// 内容数据变化（每秒刷新数字）— 高度通常不变，控制器可节流后复核
    func menuPanelViewDidChangeContent(_ view: MenuPanelView)
    /// 内容结构变化（切页 / 进出二级详情 / 列表条数变化）— 高度需立即重算
    func menuPanelViewDidChangeHeight(_ view: MenuPanelView)
    /// 选中分页变化 — 控制器据此做按页刷新（如 Token 页按需索引）
    func menuPanelViewDidSelectTab(_ view: MenuPanelView)
    /// 请求收起面板（Esc）
    func menuPanelViewDidRequestClose(_ view: MenuPanelView)
    /// 请求退出应用（⌘Q）
    func menuPanelViewDidRequestQuit(_ view: MenuPanelView)
    /// 请求切换开机自启动（标题栏齿轮菜单）
    func menuPanelViewDidRequestToggleLaunchAtStartup(_ view: MenuPanelView)
    /// 请求打开统一设置窗口（标题栏「设置…」与 ⌘,）
    ///
    /// - Parameter section: 要直接落到的分类（nil = 上次/默认页）
    func menuPanelViewDidRequestSettings(_ view: MenuPanelView, section: SettingsSection?)
}

// MARK: - 面板根视图

/// 菜单栏面板根视图 — 顶部细分段六 tab + 互斥内容区
///
/// 背景分三层（自下而上）：**玻璃**（macOS 26+ `NSGlassEffectView`，可被档位或开关关掉）
/// → **不透明基色层**（`theme.surface`，alpha 0.82）→ 内容。
/// 基色层是必须的：真实 popover 合成下单纯用 `.popover` 材质会把背景压成中灰、
/// 与语义文字色对比度不足（实机截图打回，见 `MenuPanelView+Backdrop` 的说明）。
/// 圆角与投影由 NSPopover 自身提供，内容层不重复绘制。
/// 内容区包在 `NSScrollView` 里：高度仍 clamp ≤520pt，但内容超出（进程变多 / 字体放大 / 多语言）
/// 时改为垂直滚动而不是被裁掉；隐式滚动条（overlay + autohides）。
/// 键盘：`←/→` 切页、`Tab`/`↑`/`↓` 在可点击行间移动、`Return`/`Space` 触发、
/// `1...N` 直接切页（N = 分段数）、`Esc` 收起、`⌘Q` 退出、`⌘,` 打开统一设置窗口。
final class MenuPanelView: NSView {

    weak var delegate: MenuPanelViewDelegate?

    /// 面板分页可见性/顺序偏好（构造器注入存储，测试与取证可用隔离 suite，不污染真实偏好）
    let panelTabPreferences: PanelTabPreferences

    /// 面板底（玻璃 + 基色层）；层级恒在所有内容之下，由 `installBackdrop()` 安装
    let backdrop = MenuPanelBackdropView()

    let tabBar = MenuTabBarView()
    /// 设置菜单入口（标题栏右侧齿轮：传送设置 / 开机自启动 / 退出）
    let settingsButton = NSPopUpButton(frame: .zero, pullsDown: true)
    let networkPane = NetworkPaneView()
    let clipboardPane = ClipboardPaneView()
    let transferPane = TransferPaneView()
    let billingPane = BillingPaneView()
    let tokenPane = TokenPaneView()
    let systemPane = SystemPaneView()

    /// 开机自启动当前状态（设置菜单勾选态，由控制器同步）
    var launchAtStartupEnabled = false

    /// 可滚动内容区（高度 clamp 后仍能容纳超高内容）
    // 放宽为 internal：DEBUG 快照扩展（MenuPanelView+Snapshot）要读文档高度与视口
    let scrollView = NSScrollView()
    /// 分页容器（作为 scrollView 的 documentView；flipped 保证初始停在顶部）
    // 放宽为 internal：DEBUG 快照扩展要滚它
    let paneStack = MenuPanelDocumentStack()
    /// 放宽为 internal（含 setter）：分页偏好事件驱动要重设当前页，见 MenuPanelView+TabPreferences.swift
    var currentTab: MenuPanelTab = .network
    /// 当前键盘聚焦下标（行在前、卡片在后；nil = 未聚焦任何元素）
    /// 键盘焦点下标（行与卡片共享；键盘处理拆在 MenuPanelView+Keyboard.swift，故为 internal）
    var focusedIndex: Int?

    /// 分页偏好变更观察者（注册与移除都在 MenuPanelView+TabPreferences.swift，故为 internal）
    nonisolated(unsafe) var panelTabsObserver: NSObjectProtocol?

    // MARK: - 初始化

    init(storage: any KeyValueStorage = AppContext.shared.storage) {
        self.panelTabPreferences = PanelTabPreferences(storage: storage)
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        paneStack.orientation = .vertical
        paneStack.alignment = .leading
        paneStack.spacing = 0
        paneStack.addArrangedSubview(networkPane)
        paneStack.addArrangedSubview(clipboardPane)
        paneStack.addArrangedSubview(transferPane)
        paneStack.addArrangedSubview(billingPane)
        paneStack.addArrangedSubview(tokenPane)
        paneStack.addArrangedSubview(systemPane)
        paneStack.translatesAutoresizingMaskIntoConstraints = false

        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = paneStack
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        // 文档视图宽度跟随可视区（内容只做垂直滚动），高度由分页内容自然撑开
        NSLayoutConstraint.activate([
            paneStack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            paneStack.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            paneStack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            paneStack.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        ])

        // 标题栏：分段控件 + 右侧齿轮（设置菜单）
        configureSettingsButton()

        // 设置入口已收口到状态栏右键菜单 / 主菜单，面板内不再显示齿轮
        let headerStack = NSStackView(views: [tabBar])
        headerStack.orientation = .horizontal
        headerStack.alignment = .centerY
        headerStack.spacing = 8
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        let contentStack = NSStackView(views: [headerStack, scrollView])
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentStack)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: MenuPanelStyle.panelWidth),
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: MenuPanelStyle.inset),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -MenuPanelStyle.inset),
            contentStack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -MenuPanelStyle.inset),
        ])
        headerStack.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        // 设置入口已隐藏到状态栏右键菜单，分段控件占满标题栏
        tabBar.widthAnchor.constraint(equalTo: headerStack.widthAnchor).isActive = true
        scrollView.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        // 各页都撑满面板内容宽度（NSStackView 的 leading 对齐不会自动拉伸子视图）
        for pane in [networkPane, clipboardPane, transferPane, billingPane, tokenPane, systemPane] {
            pane.widthAnchor.constraint(equalTo: paneStack.widthAnchor).isActive = true
        }

        tabBar.visibleTabs = panelTabPreferences.orderedVisibleTabs
        if !tabBar.visibleTabs.contains(currentTab) {
            currentTab = tabBar.visibleTabs.first ?? .network
        }
        tabBar.onSelect = { [weak self] tab in
            self?.select(tab: tab)
        }
        // 系统页进出详情：面板高度重算 + 滚动归零 + 返回时把焦点还给卡片
        systemPane.onContentHeightChange = { [weak self] in
            guard let self else { return }
            // 二级详情是结构变化：立即重算，避免高度滞后于翻页
            self.delegate?.menuPanelViewDidChangeHeight(self)
        }
        systemPane.onRequestScrollToTop = { [weak self] in
            self?.scrollToTop()
        }
        systemPane.onRestoreCardFocus = { [weak self] card in
            self?.focus(card: card)
        }
        applyTab()
        observePanelTabChanges()
        installBackdrop()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    nonisolated deinit {
        if let panelTabsObserver {
            NotificationCenter.default.removeObserver(panelTabsObserver)
        }
    }

    // MARK: - 背景
    //
    // 底色与玻璃都交给 `backdrop`（MenuPanelView+Backdrop.swift）：本体不再自绘不透明底，
    // 也不监听外观变化——那两件事都在 backdrop 里做，避免同一块底被画两遍。

    /// 内容所需高度（pt）：顶 10 + 分段 28 + 间距 12 + 当前页高度 + 底部留白 12
    ///
    /// 控制器据此设置 popover.contentSize（clamp ≤ MenuPanelStyle.maxHeight）；
    /// 超出上限时由内部 NSScrollView 接管滚动，不做硬截断。
    var desiredContentHeight: CGFloat {
        // 只布局当前页子树：分段条与其余五页不参与高度计算，
        // 原先的整树 layoutSubtreeIfNeeded 在展开态是 AutoLayout 的第一大来源
        activePane.layoutSubtreeIfNeeded()
        let paneHeight = activePane.fittingSize.height
        return 10 + MenuTabBarView.barHeight + 12 + paneHeight + MenuPanelStyle.inset
    }

    /// 轻量高度签名（不触发布局）
    ///
    /// 高度 = 固定前缀 + 当前页 fittingSize，而当前页高度只在结构变化时才变：
    /// 切页、进出二级详情、列表条数变化。用「分页 + 可交互行数」作签名即可覆盖这些场景，
    /// 而纯数据刷新（数字变了、行数没变）签名不变，控制器据此跳过布局。
    var contentHeightSignature: String {
        "\(currentTab.rawValue)#\(activePane.focusableRows.count)"
    }

    // MARK: - 分页切换

    /// 切换分页（键盘 ←/→、点击分段、数字键均走这里）
    func select(tab: MenuPanelTab) {
        guard tab != currentTab else { return }
        currentTab = tab
        tabBar.selected = tab
        applyTab()
        setFocus(index: nil)
        // 切页一定会改高度：走立即重算通道，不等节流（否则切页瞬间高度会滞后）
        delegate?.menuPanelViewDidChangeHeight(self)
        delegate?.menuPanelViewDidSelectTab(self)
    }

    /// 相邻分页切换（←/→ 时使用，循环）
    /// 左右方向键切页（键盘处理在 MenuPanelView+Keyboard.swift，故为 internal）
    func switchTab(by delta: Int) {
        let all = tabBar.visibleTabs
        let count = all.count
        guard let index = all.firstIndex(of: currentTab) else { return }
        let next = ((index + delta) % count + count) % count
        select(tab: all[next])
    }

    /// 应用当前分页：仅显示选中页（隐藏的 arranged subview 由 NSStackView 折叠）
    // 放宽为 internal：分页偏好事件驱动切页后要重应用，见 MenuPanelView+TabPreferences.swift
    func applyTab() {
        networkPane.isHidden = currentTab != .network
        clipboardPane.isHidden = currentTab != .clipboard
        transferPane.isHidden = currentTab != .transfer
        billingPane.isHidden = currentTab != .credits
        tokenPane.isHidden = currentTab != .token
        systemPane.isHidden = currentTab != .system
        tabBar.selected = currentTab
    }

    /// 当前页
    /// 当前可见分页（键盘遍历在 MenuPanelView+Keyboard.swift，故为 internal）
    var activePane: MenuPanelPaneView {
        switch currentTab {
        case .network: return networkPane
        case .clipboard: return clipboardPane
        case .transfer: return transferPane
        case .credits: return billingPane
        case .token: return tokenPane
        case .system: return systemPane
        }
    }

    // MARK: - 数据更新（由控制器调用）
    //
    // 各分页的数据转发已拆到 `MenuPanelView+DataUpdates.swift`：
    // 主文件贴近单文件 15 KiB 上限，接入系统页前先行拆分。

    /// 清除键盘焦点（面板收起时调用）
    func resetKeyboardFocus() {
        setFocus(index: nil)
    }

    /// 剪贴板页行内提示
    func showClipboardHint(_ message: String) {
        clipboardPane.showHint(message)
    }

    /// 内容滚动回顶部（进出系统页详情时都从顶部开始读）
    func scrollToTop() {
        layoutSubtreeIfNeeded()
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}

// MARK: - 可滚动内容容器

/// 分页容器 — flipped，保证作为 NSScrollView.documentView 时初始停在顶部
///
/// 放宽为 internal：`paneStack` 属性已放宽给 DEBUG 快照扩展，其类型不能是 private
final class MenuPanelDocumentStack: NSStackView {
    override var isFlipped: Bool { true }
}