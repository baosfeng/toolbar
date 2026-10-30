import AppKit
import NetworkMonitorCore

// MARK: - 面板根视图代理

/// 面板根视图事件回调
@MainActor
protocol MenuPanelViewDelegate: AnyObject {
    /// 内容尺寸可能变化（切页 / 数据条数变化）— 控制器据此调整 popover 高度
    func menuPanelViewDidChangeContent(_ view: MenuPanelView)
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
/// 背景是**不透明**的 `NSColor.windowBackgroundColor`（跟随系统外观），不再叠 NSVisualEffectView 材质：
/// 真实 popover 合成下 `.popover` 材质会把背景压成中灰，与语义文字色对比度不足（实机截图打回）。
/// 圆角与投影由 NSPopover 自身提供，内容层不重复绘制。
/// 内容区包在 `NSScrollView` 里：高度仍 clamp ≤520pt，但内容超出（进程变多 / 字体放大 / 多语言）
/// 时改为垂直滚动而不是被裁掉；隐式滚动条（overlay + autohides）。
/// 键盘：`←/→` 切页、`Tab`/`↑`/`↓` 在可点击行间移动、`Return`/`Space` 触发、
/// `1...N` 直接切页（N = 分段数）、`Esc` 收起、`⌘Q` 退出、`⌘,` 打开统一设置窗口。
final class MenuPanelView: NSView {

    weak var delegate: MenuPanelViewDelegate?

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
    private let scrollView = NSScrollView()
    /// 分页容器（作为 scrollView 的 documentView；flipped 保证初始停在顶部）
    private let paneStack = MenuPanelDocumentStack()
    private(set) var currentTab: MenuPanelTab = .network
    /// 当前键盘聚焦下标（行在前、卡片在后；nil = 未聚焦任何元素）
    private var focusedIndex: Int?

    // MARK: - 初始化

    init() {
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

        let headerStack = NSStackView(views: [tabBar, settingsButton])
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
        // 齿轮 24 + 间距 8 之外宽度归分段控件
        tabBar.widthAnchor.constraint(equalTo: headerStack.widthAnchor, constant: -32).isActive = true
        scrollView.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        // 各页都撑满面板内容宽度（NSStackView 的 leading 对齐不会自动拉伸子视图）
        for pane in [networkPane, clipboardPane, transferPane, billingPane, tokenPane, systemPane] {
            pane.widthAnchor.constraint(equalTo: paneStack.widthAnchor).isActive = true
        }

        tabBar.onSelect = { [weak self] tab in
            self?.select(tab: tab)
        }
        // 系统页进出详情：面板高度重算 + 滚动归零 + 返回时把焦点还给卡片
        systemPane.onContentHeightChange = { [weak self] in
            guard let self else { return }
            self.delegate?.menuPanelViewDidChangeContent(self)
        }
        systemPane.onRequestScrollToTop = { [weak self] in
            self?.scrollToTop()
        }
        systemPane.onRestoreCardFocus = { [weak self] card in
            self?.focus(card: card)
        }
        applyTab()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    // MARK: - 背景

    /// 不透明底色（windowBackgroundColor 随外观切换：浅色近白、深色近黑）
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        super.draw(dirtyRect)
    }

    /// 系统外观切换时重绘底色（避免 layer 缓存旧颜色）
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    /// 内容所需高度（pt）：顶 10 + 分段 28 + 间距 12 + 当前页高度 + 底部留白 12
    ///
    /// 控制器据此设置 popover.contentSize（clamp ≤ MenuPanelStyle.maxHeight）；
    /// 超出上限时由内部 NSScrollView 接管滚动，不做硬截断。
    var desiredContentHeight: CGFloat {
        layoutSubtreeIfNeeded()
        let paneHeight = activePane.fittingSize.height
        return 10 + MenuTabBarView.barHeight + 12 + paneHeight + MenuPanelStyle.inset
    }

#if DEBUG
    /// 快照自证专用：返回（文档高度, 滚动视口高度）
    func snapshotScrollMetrics() -> (document: CGFloat, viewport: CGFloat) {
        layoutSubtreeIfNeeded()
        return (paneStack.frame.height, scrollView.contentView.bounds.height)
    }

    /// 快照自证专用：把内容滚到指定比例（0 = 顶部，1 = 底部）
    func scrollForSnapshot(fraction: CGFloat) {
        layoutSubtreeIfNeeded()
        let maxY = max(0, paneStack.frame.height - scrollView.contentView.bounds.height)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: maxY * min(max(fraction, 0), 1)))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    /// 快照自证专用：滚到内容底部
    func scrollToBottomForSnapshot() {
        layoutSubtreeIfNeeded()
        let maxY = max(0, paneStack.frame.height - scrollView.contentView.bounds.height)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: maxY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
#endif

    // MARK: - 分页切换

    /// 切换分页（键盘 ←/→、点击分段、数字键均走这里）
    func select(tab: MenuPanelTab) {
        guard tab != currentTab else { return }
        currentTab = tab
        tabBar.selected = tab
        applyTab()
        setFocus(index: nil)
        delegate?.menuPanelViewDidChangeContent(self)
        delegate?.menuPanelViewDidSelectTab(self)
    }

    /// 相邻分页切换（←/→ 时使用，循环）
    private func switchTab(by delta: Int) {
        let all = MenuPanelTab.allCases
        let count = all.count
        guard let index = all.firstIndex(of: currentTab) else { return }
        let next = ((index + delta) % count + count) % count
        select(tab: all[next])
    }

    /// 应用当前分页：仅显示选中页（隐藏的 arranged subview 由 NSStackView 折叠）
    private func applyTab() {
        networkPane.isHidden = currentTab != .network
        clipboardPane.isHidden = currentTab != .clipboard
        transferPane.isHidden = currentTab != .transfer
        billingPane.isHidden = currentTab != .credits
        tokenPane.isHidden = currentTab != .token
        systemPane.isHidden = currentTab != .system
        tabBar.selected = currentTab
    }

    /// 当前页
    private var activePane: MenuPanelPaneView {
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

    // MARK: - 键盘可达

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let characters = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if flags.contains(.command) {
            switch characters {
            case "q": delegate?.menuPanelViewDidRequestQuit(self)
            case ",": delegate?.menuPanelViewDidRequestSettings(self, section: nil)
            default: super.keyDown(with: event)
            }
            return
        }

        switch Int(event.keyCode) {
        case 53:  // Esc：系统页详情先返回首屏，否则收起面板
            if currentTab == .system, systemPane.isShowingDetail {
                systemPane.showOverview()
            } else {
                delegate?.menuPanelViewDidRequestClose(self)
            }
        case 48:  // Tab
            moveFocus(by: flags.contains(.shift) ? -1 : 1)
        case 126:  // ↑
            moveFocus(by: -1)
        case 125:  // ↓
            moveFocus(by: 1)
        case 123:  // ←
            switchTab(by: -1)
        case 124:  // →
            switchTab(by: 1)
        case 36, 49, 76:  // Return / Space / 小键盘 Enter
            activateFocusedTarget()
        default:
            if let number = Int(characters), number >= 1, number <= MenuPanelTab.allCases.count,
               let tab = MenuPanelTab(rawValue: number - 1) {
                select(tab: tab)
                return
            }
            super.keyDown(with: event)
        }
    }

    /// 在可点击元素之间移动键盘焦点（行在前、卡片在后；循环）
    private func moveFocus(by delta: Int) {
        let count = activePane.focusableRows.count + activePane.focusableCards.count
        guard count > 0 else { return }
        let next: Int
        if let current = focusedIndex {
            next = ((current + delta) % count + count) % count
        } else {
            next = delta >= 0 ? 0 : count - 1
        }
        setFocus(index: next)
    }

    /// 设置聚焦元素（nil 清除；行与卡片共享一条焦序遍历）
    private func setFocus(index: Int?) {
        let rows = activePane.focusableRows
        let cards = activePane.focusableCards
        let count = rows.count + cards.count
        let validIndex = index.flatMap { (0..<count).contains($0) ? $0 : nil }
        for (rowIndex, row) in rows.enumerated() {
            row.setKeyboardFocused(rowIndex == validIndex)
        }
        for (cardIndex, card) in cards.enumerated() {
            card.setCardKeyboardFocused(rows.count + cardIndex == validIndex)
        }
        focusedIndex = validIndex
    }

    /// 触发当前聚焦元素（与点击同路径）
    private func activateFocusedTarget() {
        guard let index = focusedIndex else { return }
        let rows = activePane.focusableRows
        let cards = activePane.focusableCards
        if rows.indices.contains(index) {
            rows[index].activate()
        } else if cards.indices.contains(index - rows.count) {
            cards[index - rows.count].activateCard()
        }
    }

    /// 把键盘焦点还给指定卡片（从系统页详情返回时）
    func focus(card: SystemCardView) {
        let rows = activePane.focusableRows
        guard let index = activePane.focusableCards.firstIndex(where: { $0 === card }) else {
            return
        }
        setFocus(index: rows.count + index)
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
private final class MenuPanelDocumentStack: NSStackView {
    override var isFlipped: Bool { true }
}