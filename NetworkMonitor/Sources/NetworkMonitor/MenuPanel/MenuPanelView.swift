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
    /// 请求打开剪贴板设置（⌘,）
    func menuPanelViewDidRequestClipboardSettings(_ view: MenuPanelView)
}

// MARK: - 面板根视图

/// 菜单栏面板根视图 — 顶部细分段三 tab + 互斥内容区
///
/// 背景用 `NSVisualEffectView(.popover)` 材质，颜色全部走 `NSColor` 语义色，深浅色自适应。
/// 键盘：`←/→` 切页、`Tab`/`↑`/`↓` 在可点击行间移动、`Return`/`Space` 触发、
/// `1/2/3` 直接切页、`Esc` 收起、`⌘Q` 退出、`⌘,` 打开剪贴板设置。
final class MenuPanelView: NSVisualEffectView {

    weak var delegate: MenuPanelViewDelegate?

    let tabBar = MenuTabBarView()
    let networkPane = NetworkPaneView()
    let clipboardPane = ClipboardPaneView()
    let systemPane = SystemPaneView()

    private let paneStack = NSStackView()
    private(set) var currentTab: MenuPanelTab = .network
    /// 当前键盘聚焦行下标（nil = 未聚焦任何行）
    private var focusedRowIndex: Int?

    // MARK: - 初始化

    init() {
        super.init(frame: .zero)
        material = .popover
        blendingMode = .behindWindow
        state = .active
        translatesAutoresizingMaskIntoConstraints = false

        paneStack.orientation = .vertical
        paneStack.alignment = .leading
        paneStack.spacing = 0
        paneStack.addArrangedSubview(networkPane)
        paneStack.addArrangedSubview(clipboardPane)
        paneStack.addArrangedSubview(systemPane)

        let contentStack = NSStackView(views: [tabBar, paneStack])
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
        tabBar.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        paneStack.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        // 三页都撑满面板内容宽度（NSStackView 的 leading 对齐不会自动拉伸子视图）
        for pane in [networkPane, clipboardPane, systemPane] {
            pane.widthAnchor.constraint(equalTo: paneStack.widthAnchor).isActive = true
        }

        tabBar.onSelect = { [weak self] tab in
            self?.select(tab: tab)
        }
        applyTab()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

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
        tabBar.selected = currentTab
    }

    /// 当前页
    private var activePane: MenuPanelPaneView {
        switch currentTab {
        case .network: return networkPane
        case .clipboard: return clipboardPane
        case .system: return systemPane
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
