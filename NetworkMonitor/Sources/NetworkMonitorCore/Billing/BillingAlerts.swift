import Foundation

// MARK: - 额度阈值

/// 提醒阈值 — 剩余百分比从高到低；跌破哪一档就提醒哪一档
///
/// 最低档是 2%：1% 及以下由「用尽」接管（见 `exhaustedPercent`）。
/// 评估器先判用尽再判阈值，两者覆盖的点不重叠，所以「用尽线内既报用尽又报偏低」不会发生。
public enum BillingAlertThresholds {
    /// 阈值列表（降序）
    public static let percentages: [Int] = [5, 4, 3, 2]

    /// 用尽线（剩余百分比，默认 1%）
    ///
    /// 跌破这条线才算「用尽」，是唯一的低额度硬信号；阈值列表只做提前预告。
    public static let exhaustedPercent: Double = 1

    /// 当前剩余比例命中的阈值（3.7% → 4，6% → nil，0.5% → 1）
    ///
    /// 取「不小于当前剩余值的最小阈值」，即最近跨过的那一档；
    /// 一次跳变跨多档（如 6% → 3%）时只命中最低档，避免连续轰炸。
    public static func reachedThreshold(remainingFraction: Double) -> Int? {
        let percent = remainingFraction * 100
        guard percent >= 0 else { return nil }
        return percentages.last { Double($0) >= percent }
    }

    /// 剩余是否已到用尽线（负值按 0 处理）
    public static func isExhausted(remainingFraction: Double) -> Bool {
        remainingFraction * 100 <= exhaustedPercent
    }
}

// MARK: - 评估选项

/// 评估选项 — 各类通知的开关与回升参数（由 `BillingAlertPreferences` 组装）
///
/// 评估器保持纯函数：偏好读取留在可执行目标，这里只接收结果，
/// 因此「关掉恢复通知后不再产生恢复提醒」也可以直接断言。
public struct BillingAlertOptions: Sendable, Equatable {
    /// 是否产生「额度用尽」提醒
    public var notifyExhausted: Bool
    /// 是否产生「额度偏低」预告（5% … 2%）
    public var notifyThresholds: Bool
    /// 是否产生「额度已恢复」提醒（仅对本周期曾用尽的额度生效）
    public var notifyRecovered: Bool
    /// 是否产生「额度回升」提醒
    public var notifyRecovery: Bool
    /// 回升阈值（百分点）
    public var recoveryMinimumPercent: Double
    /// 回升通知冷却（秒）
    public var recoveryCooldown: TimeInterval

    public init(notifyExhausted: Bool = true,
                notifyThresholds: Bool = true,
                notifyRecovered: Bool = true,
                notifyRecovery: Bool = true,
                recoveryMinimumPercent: Double = 10,
                recoveryCooldown: TimeInterval = 3_600) {
        self.notifyExhausted = notifyExhausted
        self.notifyThresholds = notifyThresholds
        self.notifyRecovered = notifyRecovered
        self.notifyRecovery = notifyRecovery
        self.recoveryMinimumPercent = recoveryMinimumPercent
        self.recoveryCooldown = recoveryCooldown
    }
}

// MARK: - 提醒状态

/// 单个额度的提醒状态（持久化到偏好）
///
/// 除「已提醒阈值」外还存三份**观测基线**：上次剩余比例、上次窗口与上次重置时刻。
/// 恢复通知需要「相邻两次观测」才能判周期切换，因此每次评估都要刷新基线。
///
/// `exhaustedCycleID` 是恢复通知的唯一开关：它记录**最近一次用尽发生在哪个周期**。
/// 只有非 nil 的额度在切周期时才发「已恢复」，没用尽过的额度换多少轮窗口都静默。
public struct BillingAlertState: Codable, Sendable, Equatable {
    /// 周期标识（窗口 cycleID，或重置时刻 ISO 值；nil = 服务端未给周期）
    public var cycleID: String?
    /// 已提醒过的阈值（0 = 尚未提醒）
    public var notifiedThreshold: Int
    /// 上次观测到的剩余比例（回升判定基线）
    public var lastRemainingFraction: Double?
    /// 上次观测到的窗口（重置判定基线）
    public var lastWindow: BillingQuotaWindow?
    /// 上次观测到的重置时刻（无窗口信息的 provider 用它判重置）
    public var lastResetsAt: Date?
    /// 上次观测时刻
    public var lastObservedAt: Date?
    /// 已就哪个周期发过「已恢复」通知（同一周期只发一次）
    public var lastResetNotifiedCycleID: String?
    /// 上次回升通知时刻（冷却判定）
    public var lastRecoveryNotifiedAt: Date?
    /// 最近一次用尽发生的周期（nil = 从未用尽；老状态 JSON 缺此字段即 nil）
    public var exhaustedCycleID: String?

    public init(cycleID: String? = nil, notifiedThreshold: Int = 0,
                lastRemainingFraction: Double? = nil, lastWindow: BillingQuotaWindow? = nil,
                lastResetsAt: Date? = nil, lastObservedAt: Date? = nil,
                lastResetNotifiedCycleID: String? = nil,
                lastRecoveryNotifiedAt: Date? = nil,
                exhaustedCycleID: String? = nil) {
        self.cycleID = cycleID
        self.notifiedThreshold = notifiedThreshold
        self.lastRemainingFraction = lastRemainingFraction
        self.lastWindow = lastWindow
        self.lastResetsAt = lastResetsAt
        self.lastObservedAt = lastObservedAt
        self.lastResetNotifiedCycleID = lastResetNotifiedCycleID
        self.lastRecoveryNotifiedAt = lastRecoveryNotifiedAt
        self.exhaustedCycleID = exhaustedCycleID
    }
}

// MARK: - 评估器

/// 额度提醒评估器 — 输入余额快照与已提醒状态，输出本次应发提醒与更新后的状态
///
/// 规则：
/// - 每个额度资源（内含额度 / 每个百分比限额）独立记录，键为 `providerID.resourceID`；
/// - 用尽：剩余跌破用尽线（默认 1%）时提醒一次，同一周期不再重发，也不再补发更低档的偏低；
/// - 偏低：5% … 2% 只做预告，本周期已发过用尽就不再单独发；断崖跳变只留用尽一条；
/// - 恢复：周期切换（或剩余回到用尽线以上）且**上一周期该资源用尽过**才发，否则静默；
/// - 回升：相邻两次观测剩余上升达到阈值时提醒一次（有冷却，不被恢复占用）；
/// - 恢复当轮不再叠加回升：恢复文案已经表达「额度回来了」，两条同时到只会吵。
public enum BillingAlertEvaluator {

    /// 评估一次余额快照
    public static func evaluate(balance: BillingBalance,
                                providerID: String,
                                state: [String: BillingAlertState],
                                now: Date = Date(),
                                options: BillingAlertOptions = BillingAlertOptions())
        -> (alerts: [BillingAlert], state: [String: BillingAlertState]) {
        var alerts: [BillingAlert] = []
        var updated = state
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        func consider(resourceID: String, title: String, fraction: Double,
                      window: BillingQuotaWindow?, resetAt: Date?) {
            let key = "\(providerID).\(resourceID)"
            let previous = state[key]
            var current = previous ?? BillingAlertState()

            let didReset = BillingRecoveryRule.isReset(previousState: previous, window: window, resetAt: resetAt)
            let cycleID = window?.cycleID ?? resetAt.map { formatter.string(from: $0) }
            // 无周期信息的 provider 用空串占位：nil 表示「从未用尽」，两者必须能区分，
            // 否则「不加区分地拿 nil == nil」会让第一次用尽被自己拦住。
            let exhaustionKey = cycleID ?? ""
            let windowLabel = window?.title ?? title
            let exhaustedNow = BillingAlertThresholds.isExhausted(remainingFraction: fraction)
            var recoveredThisRound = false

            // 1) 恢复：只对本周期用尽过的额度生效，没用尽过的一律静默。
            //    来源有两个 —— 窗口切周期（重置回满）与同一周期内回到用尽线以上（服务端补额度）。
            //    同一周期只发一次：窗口切换且该周期已通知过恢复时不再重复。
            // 窗口已切到新周期，且该周期已经发过一条恢复 → 不再重发
            let resetAlreadyNotified = didReset
                && !BillingRecoveryRule.shouldNotifyReset(previousState: current, cycleID: cycleID)
            if !exhaustedNow, !resetAlreadyNotified,
               BillingRecoveryRule.wasExhaustedInPreviousCycle(previous) {
                // 记录一律清掉（关掉恢复通知也要让状态自洽，否则回升类提醒会被永久挡住）
                current.exhaustedCycleID = nil
                // 恢复后的剩余仍可能落在偏低区间（用尽线到 5% 之间）：记下当前档次，
                // 同一档不再重复预告，继续下跌到更低档时才再提一次。
                current.notifiedThreshold = BillingAlertThresholds.reachedThreshold(remainingFraction: fraction) ?? 0
                if didReset { current.lastResetNotifiedCycleID = cycleID }
                // 本轮不再叠加回升：从用尽里回来的这一轮，回暖由恢复这一类表达
                recoveredThisRound = true
                if options.notifyRecovered {
                    alerts.append(BillingAlert(key: key, providerID: providerID, resourceTitle: title,
                                               kind: .recovered, remainingPercent: fraction * 100,
                                               recoveredPercent: nil, windowTitle: windowLabel,
                                               resetAt: resetAt))
                }
            }

            // 2) 余额回升（周期切换与恢复当轮都跳过；有冷却）
            //
            // 「窗口重置回满」不是回升：30% → 100% 若按回升发提醒，就又变回
            // 「每 5 小时一条通知」—— 用户明确否掉的就是这个。
            if !didReset, !recoveredThisRound, options.notifyRecovery,
               BillingRecoveryRule.isCooldownElapsed(lastNotifiedAt: current.lastRecoveryNotifiedAt,
                                                     now: now, cooldown: options.recoveryCooldown) {
                let recovered = BillingRecoveryRule.recoveredPercent(from: previous?.lastRemainingFraction,
                                                                     to: fraction)
                if BillingRecoveryRule.shouldNotifyRecovery(recoveredPercent: recovered,
                                                            minimumPercent: options.recoveryMinimumPercent) {
                    alerts.append(BillingAlert(key: key, providerID: providerID, resourceTitle: title,
                                               kind: .balanceRecovered, remainingPercent: fraction * 100,
                                               recoveredPercent: recovered,
                                               windowTitle: windowLabel, resetAt: resetAt))
                    current.lastRecoveryNotifiedAt = now
                }
            }

            // 3) 用尽与偏低：周期切过就重新计数
            if cycleID != current.cycleID || didReset {
                current.notifiedThreshold = 0
            }
            current.cycleID = cycleID

            // 3a) 用尽：本周期只发一次，且不再补发更低档的偏低
            if exhaustedNow {
                // 用尽记录只在真发过用尽时写入：关掉用尽提醒的用户，后续也不该收到「已恢复」
                if current.exhaustedCycleID != exhaustionKey, options.notifyExhausted {
                    alerts.append(BillingAlert(key: key, providerID: providerID, resourceTitle: title,
                                               kind: .exhausted, remainingPercent: fraction * 100,
                                               recoveredPercent: nil, windowTitle: windowLabel,
                                               resetAt: resetAt))
                    current.exhaustedCycleID = exhaustionKey
                }
                // 用尽线内不可能再命中任何偏低档，无需额外抑制
            } else if let threshold = BillingAlertThresholds.reachedThreshold(remainingFraction: fraction) {
                if current.notifiedThreshold == 0 || threshold < current.notifiedThreshold {
                    // 与「已恢复」同一轮不再追加偏低：恢复正文已经写了当前剩余
                    if options.notifyThresholds, !recoveredThisRound {
                        alerts.append(BillingAlert(key: key, providerID: providerID, resourceTitle: title,
                                                   kind: .threshold(threshold),
                                                   remainingPercent: fraction * 100,
                                                   recoveredPercent: nil, windowTitle: windowLabel,
                                                   resetAt: resetAt))
                    }
                    current.notifiedThreshold = threshold
                }
            } else if current.notifiedThreshold != 0 {
                // 回到 5% 以上：清空已提醒记录，下次下降可再次提醒
                current.notifiedThreshold = 0
            }

            // 4) 刷新观测基线（恢复 / 回升判定的输入）
            current.lastRemainingFraction = fraction
            if let window { current.lastWindow = window }
            if let resetAt { current.lastResetsAt = resetAt }
            current.lastObservedAt = now
            updated[key] = current
        }

        if let included = balance.included {
            consider(resourceID: "included",
                     title: "内含",
                     fraction: included.remainingFraction,
                     window: included.period.map {
                         BillingQuotaWindow(kind: .monthly, duration: $0.duration, resetsAt: $0.end)
                     },
                     resetAt: included.period?.end)
        }
        for limit in balance.percentLimits {
            consider(resourceID: limit.id,
                     title: limit.title,
                     fraction: limit.remainingFraction,
                     window: limit.window,
                     resetAt: limit.resetsAt)
        }
        return (alerts, updated)
    }
}
