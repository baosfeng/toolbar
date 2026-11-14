import Foundation

// MARK: - 额度推送回拉的放行判据

/// 「额度推送 → 面板通知 → 再拉额度」这条反馈边的放行判据
///
/// 额度刷新是**推送式**的：`BillingMonitor.refresh()` 同步走到 `emit()` → 面板 `updateBilling`
/// → `menuPanelViewDidChangeContent`，而该回调在额度页又会回头调 `refresh()`。
/// 只要这一轮 refresh 每次都 emit（provider 全未配置的空态、states 每轮都算「变了」就是这种情况），
/// 这条边就会**同步无限递归**，直到把栈写爆（崩溃报告里 faulting thread 是同一段 5 帧循环，
/// 地址落在 Stack Guard 区域）。
///
/// 判据只有一条：由一次推送引起的这次内容通知，不再回头拉数据；
/// 常规节拍（tick 的 60 秒节流）与切页补数据都不经过这条边，不受影响。
public enum BillingRefreshGate {
    /// 内容变更通知是否应该回头拉一次额度
    /// - Parameters:
    ///   - isBillingTab: 当前可见分页是否是额度页
    ///   - isPushingSnapshot: 此刻是否正在消费一次额度推送
    public static func shouldPullForContentChange(isBillingTab: Bool,
                                                  isPushingSnapshot: Bool) -> Bool {
        isBillingTab && !isPushingSnapshot
    }
}
