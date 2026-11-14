import Foundation

// MARK: - 额度恢复判定（纯逻辑）

/// 恢复判定的三个信号 —— 周期重置 / 余额回升 / 周窗口
///
/// 「周额度重置要能通知」这条需求拆成两个可测的判定：
/// 1. **窗口重置**：同一额度行的窗口周期标识（`cycleID`）前进，且重置时刻确实往后走；
/// 2. **余额回升**：相邻两次观测的剩余比例差值达到阈值（默认 10 个百分点）。
///
/// 首次观测（没有上一份状态）不算重置、也不算回升 —— 否则新装用户第一次刷新
/// 就会收到「额度已重置」的通知。
public enum BillingRecoveryRule {

    /// 窗口是否发生重置
    ///
    /// 判据同时要求「周期标识变化」与「重置时刻前进」：只变周期标识可能是服务端
    /// 重新计算了同一周期，只有时刻往后走才是真的进入新周期。
    public static func isWindowReset(previous: BillingQuotaWindow?,
                                     current: BillingQuotaWindow?) -> Bool {
        guard let previous, let current else { return false }
        guard previous.cycleID != current.cycleID else { return false }
        return current.resetsAt > previous.resetsAt
    }

    /// 回升的百分点（负值归 0；没有基线时为 0）
    ///
    /// 结果保留 0.1 个百分点：剩余比例是 0…1 的小数，直接乘 100 会出现
    /// `0.25 - 0.2 = 4.999999999999999` 这类噪声，让「刚好达到阈值」卡在边界外。
    public static func recoveredPercent(from previous: Double?, to current: Double) -> Double {
        guard let previous else { return 0 }
        let delta = (current - previous) * 100
        guard delta > 0 else { return 0 }
        return (delta * 10).rounded() / 10
    }

    /// 是否达到回升通知条件（阈值必须为正）
    public static func shouldNotifyRecovery(recoveredPercent: Double, minimumPercent: Double) -> Bool {
        minimumPercent > 0 && recoveredPercent >= minimumPercent
    }

    /// 是否发生重置 —— 兼容「有窗口信息」与「只有重置时刻」两类 provider
    ///
    /// 订阅型 provider（Claude / Codex / Cursor）带窗口种类，按窗口判定；
    /// 老 provider（Ollama / Open Code Go）只有 `resetsAt`，按重置时刻前进判定。
    public static func isReset(previousState: BillingAlertState?,
                               window: BillingQuotaWindow?,
                               resetAt: Date?) -> Bool {
        guard let previousState else { return false }
        if let window {
            return isWindowReset(previous: previousState.lastWindow, current: window)
        }
        guard let resetAt, let previousResetAt = previousState.lastResetsAt else { return false }
        return resetAt > previousResetAt
    }

    /// 同一窗口周期只通知一次重置（周期标识相同即同一周期）
    public static func shouldNotifyReset(previousState: BillingAlertState,
                                         cycleID: String?) -> Bool {
        guard let cycleID else { return false }
        return previousState.lastResetNotifiedCycleID != cycleID
    }

    /// 同一窗口周期只通知一次重置（窗口版便捷入口）
    public static func shouldNotifyReset(previousState: BillingAlertState,
                                         current: BillingQuotaWindow) -> Bool {
        shouldNotifyReset(previousState: previousState, cycleID: current.cycleID)
    }

    /// 回升通知是否已过冷却期（避免短时间反复触发）
    public static func isCooldownElapsed(lastNotifiedAt: Date?, now: Date,
                                         cooldown: TimeInterval) -> Bool {
        guard let lastNotifiedAt else { return true }
        return now.timeIntervalSince(lastNotifiedAt) >= max(0, cooldown)
    }
}
