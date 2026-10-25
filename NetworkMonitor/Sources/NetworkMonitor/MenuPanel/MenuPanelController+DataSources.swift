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
}
