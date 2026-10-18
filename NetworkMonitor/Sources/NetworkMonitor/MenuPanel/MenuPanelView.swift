import AppKit
import NetworkMonitorCore

// MARK: - 面板根视图代理

/// 面板根视图事件回调
@MainActor
protocol MenuPanelViewDelegate: AnyObject {
    /// 内容尺寸可能变化（切页 / 数据条数变化）— 控制器据此调整 popover 高度
    func menuPanelViewDidChangeContent(_ view: MenuPanelView)
    /// 请求收起面板（Esc）
    func menuPanelViewDidRequestClose(_ view: MenuPanelView)
    /// 请求退出应用（⌘Q）
    func menuPanelViewDidRequestQuit(_ view: MenuPanelView)
    /// 请求打开传送设置（标题栏齿轮）
    func menuPanelViewDidRequestTransferSettings(_ view: MenuPanelView)
    /// 请求打开剪贴板设置（⌘,）
    func menuPanelViewDidRequestClipboardSettings(_ view: MenuPanelView)
}

// MARK: - 面板根视图

/// 菜单栏面板根视图 — 顶部细分段三 tab + 互斥内容区
///
/// 背景是**不透明**的 `NSColor.windowBackgroundColor`（跟随系统外观），不再叠 NSVisualEffectView 材质：
/// 真实 popover 合成下 `.popover` 材质会把背景压成中灰，与语义文字色对比度不足（实机截图打回）。
/// 圆角与投影由 NSPopover 自身提供，内容层不重复绘制。
/// 内容区包在 `NSScrollView` 里：高度仍 clamp ≤520pt，但内容超出（进程变多 / 字体放大 / 多语言）
/// 时改为垂直滚动而不是被裁掉；隐式滚动条（overlay + autohides）。
/// 键盘：`←/→` 切页、`Tab`/`↑`/`↓` 在可点击行间移动、`Return`/`Space` 触发、
/// `1/2/3` 直接切页、`Esc` 收起、`⌘Q` 退出、`⌘,` 打开剪贴板设置。
final class MenuPanelView: NSView {

    weak var delegate: MenuPanelViewDelegate?

    let tabBar = MenuTabBarView()
    /// 传送设置入口（标题栏右侧齿轮）
    let transferSettingsButton = NSButton()
    let networkPane = NetworkPaneView()
    let clipboardPane = ClipboardPaneView()
    let systemPane = SystemPaneView()
    let transferPane = TransferPaneView()
    let billingPane = BillingPaneView()

    /// 可滚动内容区（高度 clamp 后仍能容纳超高内容）
    private let scrollView = NSScrollView()
    /// 分页容器（作为 scrollView 的 documentView；flipped 保证初始停在顶部）
    private let paneStack = MenuPanelDocumentStack()
    private(set) var currentTab: MenuPanelTab = .network
    /// 当前键盘聚焦行下标（nil = 未聚焦任何行）
    private var focusedRowIndex: Int?

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
        paneStack.addArrangedSubview(systemPane)
        paneStack.addArrangedSubview(transferPane)
        paneStack.addArrangedSubview(billingPane)
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

        // 标题栏：分段控件 + 右侧齿轮（传送设置）
        transferSettingsButton.image = NSImage(systemSymbolName: "gearshape",
                                               accessibilityDescription: "传送设置")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .medium))
        transferSettingsButton.isBordered = false
        transferSettingsButton.bezelStyle = .inline
        transferSettingsButton.contentTintColor = MenuPanelStyle.tertiaryText
        transferSettingsButton.toolTip = "传送设置"
        transferSettingsButton.setAccessibilityLabel("传送设置")
        transferSettingsButton.target = self
        transferSettingsButton.action = #selector(openTransferSettings)
        transferSettingsButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            transferSettingsButton.widthAnchor.constraint(equalToConstant: 24),
            transferSettingsButton.heightAnchor.constraint(equalToConstant: 24),
        ])

        let headerStack = NSStackView(views: [tabBar, transferSettingsButton])
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
        for pane in [networkPane, clipboardPane, systemPane, transferPane, billingPane] {
            pane.widthAnchor.constraint(equalTo: paneStack.widthAnchor).isActive = true
        }

        tabBar.onSelect = { [weak self] tab in
            self?.select(tab: tab)
        }
        applyTab()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 齿轮点击：交给控制器打开传送设置
    @objc private func openTransferSettings() {
        delegate?.menuPanelViewDidRequestTransferSettings(self)
    }

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
        systemPane.isHidden = currentTab != .system
        transferPane.isHidden = currentTab != .transfer
        billingPane.isHidden = currentTab != .credits
        tabBar.selected = currentTab
    }

    /// 当前页
    private var activePane: MenuPanelPaneView {
        switch currentTab {
        case .network: return networkPane
        case .clipboard: return clipboardPane
        case .system: return systemPane
        case .transfer: return transferPane
        case .credits: return billingPane
        }
    }

    // MARK: - 数据更新（由控制器调用）

    /// 实时速率（1 秒）
    func updateSpeeds(down: Double, up: Double, downHistory: [Double], upHistory: [Double]) {
        networkPane.updateSpeeds(down: down, up: up, downHistory: downHistory, upHistory: upHistory)
    }

    /// 今日流量 + 近 6 日柱状图（5 秒）
    func updateTraffic(todayRx: UInt64, todayTx: UInt64,
                       dailyBars: [MenuPanelMetrics.DailyTrafficBar]) {
        networkPane.updateTraffic(todayRx: todayRx, todayTx: todayTx, dailyBars: dailyBars)
        delegate?.menuPanelViewDidChangeContent(self)
    }

    /// 活跃进程 Top5（5 秒）
    func updateProcesses(_ processes: [ProcessNetUsage]) {
        networkPane.updateProcesses(processes)
        delegate?.menuPanelViewDidChangeContent(self)
    }

    /// 剪贴板最近条目（事件驱动 + 打开面板时强制刷新）
    func updateClipboardItems(_ items: [ClipboardItem]) {
        clipboardPane.update(items: items)
        setFocus(index: nil)
        delegate?.menuPanelViewDidChangeContent(self)
    }

    /// 系统页信息（5 秒）
    func updateSystem(ip: String, wifi: String, launchAtStartup: Bool) {
        systemPane.update(ip: ip, wifi: wifi, launchAtStartup: launchAtStartup)
    }

    /// 额度页快照（状态管理器回调）
    func updateBilling(_ snapshot: BillingMonitor.Snapshot, notifySize: Bool = true) {
        billingPane.update(snapshot)
        if notifySize {
            delegate?.menuPanelViewDidChangeContent(self)
        }
    }

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
            case ",": delegate?.menuPanelViewDidRequestClipboardSettings(self)
            default: super.keyDown(with: event)
            }
            return
        }

        switch Int(event.keyCode) {
        case 53:  // Esc
            delegate?.menuPanelViewDidRequestClose(self)
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
            activateFocusedRow()
        default:
            if let number = Int(characters), number >= 1, number <= MenuPanelTab.allCases.count,
               let tab = MenuPanelTab(rawValue: number - 1) {
                select(tab: tab)
                return
            }
            super.keyDown(with: event)
        }
    }

    /// 在可点击行之间移动键盘焦点（循环）
    private func moveFocus(by delta: Int) {
        let rows = activePane.focusableRows
        guard !rows.isEmpty else { return }
        let next: Int
        if let current = focusedRowIndex {
            next = ((current + delta) % rows.count + rows.count) % rows.count
        } else {
            next = delta >= 0 ? 0 : rows.count - 1
        }
        setFocus(index: next)
    }

    /// 设置聚焦行（nil 清除）
    private func setFocus(index: Int?) {
        let rows = activePane.focusableRows
        let validIndex = index.flatMap { rows.indices.contains($0) ? $0 : nil }
        for (rowIndex, row) in rows.enumerated() {
            row.setKeyboardFocused(rowIndex == validIndex)
        }
        focusedRowIndex = validIndex
    }

    /// 触发当前聚焦行（与点击同路径）
    private func activateFocusedRow() {
        guard let index = focusedRowIndex else { return }
        let rows = activePane.focusableRows
        guard rows.indices.contains(index) else { return }
        rows[index].activate()
    }
}

// MARK: - 可滚动内容容器

/// 分页容器 — flipped，保证作为 NSScrollView.documentView 时初始停在顶部
private final class MenuPanelDocumentStack: NSStackView {
    override var isFlipped: Bool { true }
}
