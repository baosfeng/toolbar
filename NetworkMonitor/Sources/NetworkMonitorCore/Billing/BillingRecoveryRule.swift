import Foundation

// MARK: - 额度恢复判定（纯逻辑）

/// 恢复判定的四个信号 —— 用尽记录 / 周期重置 / 余额回升 / 冷却
///
/// 「额度用尽后再恢复才通知」这条需求拆成几个可测的判定：
/// 1. **用尽门槛**：只有 `exhaustedCycleID` 记着本周期用尽过，切周期才发「已恢复」；
/// 2. **窗口重置**：同一额度行的窗口周期标识（`cycleID`）前进，且重置时刻确实往后走；
/// 3. **余额回升**：相邻两次观测的剩余比例差值达到阈值（默认 10 个百分点）。
///
/// 首次观测（没有上一份状态）不算重置、也不算回升 —— 否则新装用户第一次刷新
/// 就会收到「额度已恢复」的通知；老版本状态 JSON 同样按「没用尽过」处理。
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

    /// 上一周期该额度是否用尽过 —— 恢复通知的唯一门槛
    ///
    /// 判据是「最近一次用尽发生的周期 == 当前记录的周期」：每次评估都会刷新
    /// `cycleID`，因此 `exhaustedCycleID` 只会在用尽那一周期相等，之后周期一切换
    /// 就不再相等 —— 「上上周期用过尽」不会被误判成「上一周期用过尽」。
    ///
    /// 老状态 JSON 没有 `exhaustedCycleID` 字段（解码为 nil），因此升级后第一轮
    /// 一律按「没用尽过」处理：不会凭空给用户补发一条「额度已恢复」。
    public static func wasExhaustedInPreviousCycle(_ state: BillingAlertState?) -> Bool {
        guard let state, let exhausted = state.exhaustedCycleID else { return false }
        // 无周期标识的 provider（只有重置时刻）无法比较周期，按「曾用尽」处理
        guard let cycle = state.cycleID else { return true }
        return exhausted == cycle
    }

    /// 回升通知是否已过冷却期（避免短时间反复触发）
    public static func isCooldownElapsed(lastNotifiedAt: Date?, now: Date,
                                         cooldown: TimeInterval) -> Bool {
        guard let lastNotifiedAt else { return true }
        return now.timeIntervalSince(lastNotifiedAt) >= max(0, cooldown)
    }
}
