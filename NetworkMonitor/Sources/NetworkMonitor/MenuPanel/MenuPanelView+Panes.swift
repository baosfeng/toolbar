import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 面板根视图 · 分页懒装配

/// 分页懒装配 —— 从 `MenuPanelView.swift` 拆出（主文件贴近单文件 15 KiB 上限）
///
/// 六个分页原先在 init 里一次全建并全部进 `paneStack`（约 2800 个 layer-backed 视图、
/// 14214 条约束常驻，是启动后 footprint 的大头）。改成：冷启动只装配当前分页
/// （默认网络页，或偏好里的首屏），其余页**首次切到时**才建实例、才进 `paneStack`、
/// 才加宽度约束、才挂动作回调。对外仍暴露原来的具体类型属性，
/// 既有调用点写法不变（第一次读到才触发创建）；只读判据走 `paneIfLoaded`。
extension MenuPanelView {

    // MARK: - 只读入口

    /// 指定分页已装配则返回实例，未装配返回 nil（数据转发 / 键盘 / 偏好逻辑据此跳过）
    func paneIfLoaded(_ tab: MenuPanelTab) -> MenuPanelPaneView? { assembledPanes[tab] }

    // 以下具体类型入口供数据转发、键盘与分页偏好扩展读取（跨文件访问故为 internal）

    /// 已装配的网络页
    var networkPaneIfLoaded: NetworkPaneView? { assembledPanes[.network] as? NetworkPaneView }
    /// 已装配的剪贴板页
    var clipboardPaneIfLoaded: ClipboardPaneView? { assembledPanes[.clipboard] as? ClipboardPaneView }
    /// 已装配的额度页
    var billingPaneIfLoaded: BillingPaneView? { assembledPanes[.credits] as? BillingPaneView }
    /// 已装配的 Token 页
    var tokenPaneIfLoaded: TokenPaneView? { assembledPanes[.token] as? TokenPaneView }
    /// 已装配的系统页
    var systemPaneIfLoaded: SystemPaneView? { assembledPanes[.system] as? SystemPaneView }

    // MARK: - 六个分页（首次读到才建）

    /// 网络页
    var networkPane: NetworkPaneView { loadedPane(.network) { NetworkPaneView() } }
    /// 剪贴板页
    var clipboardPane: ClipboardPaneView { loadedPane(.clipboard) { ClipboardPaneView() } }
    /// 传送页
    var transferPane: TransferPaneView { loadedPane(.transfer) { TransferPaneView() } }
    /// 额度页
    var billingPane: BillingPaneView { loadedPane(.credits) { BillingPaneView() } }
    /// Token 页
    var tokenPane: TokenPaneView { loadedPane(.token) { TokenPaneView() } }
    /// 系统页
    var systemPane: SystemPaneView { loadedPane(.system) { SystemPaneView() } }

    // MARK: - 装配

    /// 确保某分页已装配（切页与取证路径显式调用；已装配则原样返回，不重建）
    @discardableResult
    func ensurePaneLoaded(_ tab: MenuPanelTab) -> MenuPanelPaneView {
        switch tab {
        case .network: return networkPane
        case .clipboard: return clipboardPane
        case .transfer: return transferPane
        case .credits: return billingPane
        case .token: return tokenPane
        case .system: return systemPane
        }
    }

    /// 取已装配实例；没有就建一个并装进 `paneStack`
    private func loadedPane<T: MenuPanelPaneView>(_ tab: MenuPanelTab, make: () -> T) -> T {
        if let existing = assembledPanes[tab] as? T { return existing }
        let pane = make()
        assemble(pane, for: tab)
        return pane
    }

    /// 把新页装进 `paneStack`：登记 → 显隐 → 入栈 → 宽度约束 → 系统页回调 → 外部装配回调
    private func assemble(_ pane: MenuPanelPaneView, for tab: MenuPanelTab) {
        assembledPanes[tab] = pane
        let isFirst = paneAssembly.requestAssembly(tab)
        pane.isHidden = tab != currentTab
        // 按分页声明顺序入栈：分页条与数字键口径同序，隐藏页的相对位置因此保持稳定
        paneStack.insertArrangedSubview(pane, at: min(stackIndex(for: tab),
                                                     paneStack.arrangedSubviews.count))
        // 各页都撑满面板内容宽度（NSStackView 的 leading 对齐不会自动拉伸子视图）
        pane.widthAnchor.constraint(equalTo: paneStack.widthAnchor).isActive = true
        if tab == currentTab { didAssembleCurrentPane = true }
        if tab == .system { bindSystemPaneCallbacks(on: pane) }
        // 首次进树先解析一次布局：紧随其后的高度计算只布局当前页子树，
        // 未解析宽度的新页会把 popover 高度算偏（表现为切页瞬间高度跳一下）
        layoutSubtreeIfNeeded()
        if isFirst { onPaneAssembled?(tab, pane) }
    }

    /// 新页应插入的下标 —— 已装配的页按 `MenuPanelTab` 声明顺序占位
    private func stackIndex(for tab: MenuPanelTab) -> Int {
        let order = MenuPanelTab.allCases
        guard let rank = order.firstIndex(of: tab) else { return paneStack.arrangedSubviews.count }
        return order.prefix(rank).filter { assembledPanes[$0] != nil }.count
    }

    /// 系统页回调绑定（进出详情 → 高度重算 / 滚回顶部 / 焦点还给卡片）
    ///
    /// 懒装配后不能在 init 里挂：那会立刻把系统页建出来。改为该页首次进树时挂一次。
    private func bindSystemPaneCallbacks(on pane: MenuPanelPaneView) {
        guard let system = pane as? SystemPaneView else { return }
        system.onContentHeightChange = { [weak self] in
            guard let self else { return }
            // 二级详情是结构变化：立即重算，避免高度滞后于翻页
            self.delegate?.menuPanelViewDidChangeHeight(self)
        }
        system.onRequestScrollToTop = { [weak self] in
            self?.scrollToTop()
        }
        system.onRestoreCardFocus = { [weak self] card in
            self?.focus(card: card)
        }
    }

    // MARK: - 当前页

    /// 应用当前分页：先装配当前页，再只对已装配页设显隐（未装配页根本不进视图树）
    // 放宽为 internal：分页偏好事件驱动切页后要重应用，见 MenuPanelView+TabPreferences.swift
    func applyTab() {
        // 本次切页是否首次装配：先清零，本方法内装配成功才置 true（控制器据此补首屏数据）
        didAssembleCurrentPane = false
        ensurePaneLoaded(currentTab)
        for (tab, pane) in assembledPanes { pane.isHidden = tab != currentTab }
        tabBar.selected = currentTab
    }

    /// 当前可见分页（键盘遍历、高度计算都用它；调用时一定已装配）
    // 放宽为 internal：键盘扩展（MenuPanelView+Keyboard）与高度计算跨文件使用
    var activePane: MenuPanelPaneView { ensurePaneLoaded(currentTab) }
}
