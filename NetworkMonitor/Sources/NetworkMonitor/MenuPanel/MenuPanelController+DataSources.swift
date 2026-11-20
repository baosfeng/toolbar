import AppKit
import NetworkMonitorCore
import NetworkMonitorFeatureBilling
import NetworkMonitorUI

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
                                                                           enabledProviderCount: billingMonitor.states.count,
                                                                           isPaused: billingMonitor.isPaused),
                                               notifySize: self.popover.isShown)
                }
            }
        }
    }

    // MARK: - Token

    /// Token 页刷新：先渲染已有快照，再后台按需索引（首轮索引不阻塞面板）
    ///
    /// 快照是内存里的加锁读，但仍放到后台取用：主线程在任何路径上都不再碰数据库队列；
    /// 顺手让服务判断「有未计入快照的写入」时补算一次（无脏数据即零查询）。
    func refreshToken() {
        guard let harnessUsage else { return }
        let sequence = tokenRequests.next()
        dataReadQueue.async { [harnessUsage] in
            let snapshot = harnessUsage.snapshot()
            harnessUsage.refreshSnapshotIfDirty()
            Task { @MainActor in
                guard self.tokenRequests.accepts(sequence) else { return }
                self.content.updateToken(snapshot, notifySize: false)
                // 异步渲染晚于打开时的强制算高：内容落定后补一次强制重算。
                // Token 页的可交互行数（高度签名）不随数值变化，非强制通道不会触发重算，
                // 不补这一步就会出现「展开后高度停在空内容那一档」。
                if self.popover.isShown { self.updateContentSize(force: true) }
            }
        }
        harnessUsage.refreshIfNeeded()
    }
}