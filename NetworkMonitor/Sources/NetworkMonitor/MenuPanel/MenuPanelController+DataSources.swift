import AppKit
import NetworkMonitorCore

// MARK: - 菜单面板控制器（数据源绑定）

/// 数据源回调绑定 — 从 `MenuPanelController.swift` 拆出（主文件接近单文件 15 KiB 上限）
///
/// 只绑定「状态管理器 / Token 服务 → 面板视图」这一条链路，刷新策略与动作仍在主文件与 +Actions。
/// 跨文件访问的 `popover` 由 private 放宽为 internal。
extension MenuPanelController {

    /// 额度页数据回调（状态管理器 → 面板 → 高度自适应）
    func bindBilling() {
        billingMonitor?.onUpdate = { [weak self] snapshot in
            guard let self else { return }
            // 收起时仍更新视图数据（下次打开即最新），但不触发布局与 popover 尺寸调整
            self.content.updateBilling(snapshot, notifySize: self.popover.isShown)
        }
    }

    /// Token 页事件回调：索引完成后立即重读快照（收起时只更新视图数据，不调整尺寸）
    func bindHarnessUsage() {
        guard harnessUsage != nil else { return }
        harnessObserver = NotificationCenter.default.addObserver(
            forName: AppEvents.harnessUsageChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let harnessUsage = self.harnessUsage else { return }
                self.content.updateToken(harnessUsage.snapshot(), notifySize: self.popover.isShown)
            }
        }
    }

    /// 数值单位切档回调：设置页写成偏好后发事件，这里立刻用当前快照重渲染两页数值
    ///
    /// 只重渲染、不重查：单位只是写法变化，Token 与额度数据都不变；
    /// 面板收起时同样更新视图（下次打开即新写法），不触发布局与 popover 尺寸调整。
    func bindNumberUnitStyle() {
        unitObserver = NotificationCenter.default.addObserver(
            forName: AppEvents.numberUnitStyleChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let harnessUsage = self.harnessUsage {
                    self.content.updateToken(harnessUsage.snapshot(), notifySize: self.popover.isShown)
                }
                if let billingMonitor = self.billingMonitor {
                    self.content.updateBilling(BillingMonitor.Snapshot.make(from: billingMonitor.states,
                                                                           enabledProviderCount: billingMonitor.states.count),
                                               notifySize: self.popover.isShown)
                }
            }
        }
    }

    // MARK: - 剪贴板

    /// 注册剪贴板变更通知（从主文件搬来：主文件贴近 15 KiB 上限）
    func observeClipboardChanges() {
        clipboardObserver = NotificationCenter.default.addObserver(
            forName: AppEvents.clipboardChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // 面板收起时不做渲染，下次打开会强制全量刷新
                guard self.popover.isShown else { return }
                self.refreshClipboard()
            }
        }
    }

    /// 剪贴板刷新：仓储按时间倒序取最近 5 条
    func refreshClipboard() {
#if DEBUG
        if forceEmptyDataForEvidence {
            content.updateClipboardItems([])
            return
        }
#endif
        content.updateClipboardItems(repository.fetchClipboardItems(kind: nil, limit: 5))
    }

    // MARK: - Token

    /// Token 页刷新：先渲染已有快照，再后台按需索引（首轮索引不阻塞面板）
    func refreshToken() {
        guard let harnessUsage else { return }
        content.updateToken(harnessUsage.snapshot(), notifySize: popover.isShown)
        harnessUsage.refreshIfNeeded()
    }

    /// 强制重建 Token 索引（点刷新按钮）
    func rebuildTokenIndex() {
        harnessUsage?.rebuildIndex()
    }
}
