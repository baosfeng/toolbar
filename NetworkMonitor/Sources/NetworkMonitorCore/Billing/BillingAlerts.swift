import Foundation

// MARK: - 额度阈值

/// 提醒阈值 — 剩余百分比从高到低；跌破哪一档就提醒哪一档
public enum BillingAlertThresholds {
    /// 阈值列表（降序）
    public static let percentages: [Int] = [5, 4, 3, 2, 1]

    /// 当前剩余比例命中的阈值（3.7% → 4，6% → nil，0.5% → 1）
    ///
    /// 取「不小于当前剩余值的最小阈值」，即最近跨过的那一档；
    /// 一次跳变跨多档（如 6% → 3%）时只命中最低档，避免连续轰炸。
    public static func reachedThreshold(remainingFraction: Double) -> Int? {
        let percent = remainingFraction * 100
        guard percent >= 0 else { return nil }
        return percentages.last { Double($0) >= percent }
    }
}

// MARK: - 评估选项

/// 评估选项 — 三类通知的开关与回升参数（由 `BillingAlertPreferences` 组装）
///
/// 评估器保持纯函数：偏好读取留在可执行目标，这里只接收结果，
/// 因此「关掉重置通知后不再产生重置提醒」也可以直接断言。
public struct BillingAlertOptions: Sendable, Equatable {
    /// 是否产生阈值提醒（5% / 4% / 3% / 2% / 1%）
    public var notifyThresholds: Bool
    /// 是否产生「窗口已重置」提醒
    public var notifyWindowReset: Bool
    /// 是否产生「额度已回升」提醒
    public var notifyRecovery: Bool
    /// 回升阈值（百分点）
    public var recoveryMinimumPercent: Double
    /// 回升通知冷却（秒）
    public var recoveryCooldown: TimeInterval

    public init(notifyThresholds: Bool = true,
                notifyWindowReset: Bool = true,
                notifyRecovery: Bool = true,
                recoveryMinimumPercent: Double = 10,
                recoveryCooldown: TimeInterval = 3_600) {
        self.notifyThresholds = notifyThresholds
        self.notifyWindowReset = notifyWindowReset
        self.notifyRecovery = notifyRecovery
        self.recoveryMinimumPercent = recoveryMinimumPercent
        self.recoveryCooldown = recoveryCooldown
    }
}

// MARK: - 提醒种类

/// 提醒种类 —— 文案与去重口径都按种类区分
public enum BillingAlertKind: Sendable, Equatable {
    /// 剩余跌破阈值（5…1%）
    case threshold(Int)
    /// 窗口进入新周期（会话 / 周 / 月额度重置）
    case windowReset
    /// 余额回升到阈值以上
    case balanceRecovered
}

// MARK: - 提醒状态

/// 单个额度的提醒状态（持久化到偏好）
///
/// 除「已提醒阈值」外还存两份**观测基线**：上次剩余比例与上次窗口。
/// 恢复通知需要「相邻两次观测」才能判断重置与回升，因此每次评估都要刷新基线。
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
    /// 已就哪个周期发过「重置」通知（同一周期只发一次）
    public var lastResetNotifiedCycleID: String?
    /// 上次回升通知时刻（冷却判定）
    public var lastRecoveryNotifiedAt: Date?

    public init(cycleID: String? = nil, notifiedThreshold: Int = 0,
                lastRemainingFraction: Double? = nil, lastWindow: BillingQuotaWindow? = nil,
                lastResetsAt: Date? = nil, lastObservedAt: Date? = nil,
                lastResetNotifiedCycleID: String? = nil,
                lastRecoveryNotifiedAt: Date? = nil) {
        self.cycleID = cycleID
        self.notifiedThreshold = notifiedThreshold
        self.lastRemainingFraction = lastRemainingFraction
        self.lastWindow = lastWindow
        self.lastResetsAt = lastResetsAt
        self.lastObservedAt = lastObservedAt
        self.lastResetNotifiedCycleID = lastResetNotifiedCycleID
        self.lastRecoveryNotifiedAt = lastRecoveryNotifiedAt
    }
}

// MARK: - 一条待发送的提醒

/// 一条待发送的提醒
public struct BillingAlert: Sendable, Equatable {
    /// 状态键（providerID.resourceID）
    public let key: String
    public let providerID: String
    /// 额度名称（会话 / 每周 / 内含）
    public let resourceTitle: String
    /// 提醒种类
    public let kind: BillingAlertKind
    /// 实际剩余百分比（服务端原值，不取整）
    public let remainingPercent: Double
    /// 回升百分点（仅「额度已恢复」有值）
    public let recoveredPercent: Double?
    /// 窗口展示名（会话 / 每周；仅重置通知使用）
    public let windowTitle: String?
    /// 下次重置时间
    public let resetAt: Date?

    public init(key: String, providerID: String, resourceTitle: String,
                kind: BillingAlertKind, remainingPercent: Double, recoveredPercent: Double?,
                windowTitle: String?, resetAt: Date?) {
        self.key = key
        self.providerID = providerID
        self.resourceTitle = resourceTitle
        self.kind = kind
        self.remainingPercent = remainingPercent
        self.recoveredPercent = recoveredPercent
        self.windowTitle = windowTitle
        self.resetAt = resetAt
    }

    /// 阈值类便捷构造（保留旧调用形态）
    public init(key: String, providerID: String, resourceTitle: String,
                threshold: Int, remainingPercent: Double, resetAt: Date?) {
        self.init(key: key, providerID: providerID, resourceTitle: resourceTitle,
                  kind: .threshold(threshold), remainingPercent: remainingPercent,
                  recoveredPercent: nil, windowTitle: nil, resetAt: resetAt)
    }

    /// 命中的阈值（非阈值类为 0）
    public var threshold: Int {
        if case .threshold(let value) = kind { return value }
        return 0
    }

    /// 是否「即将用尽」档（1%）
    public var isCritical: Bool {
        if case .threshold(let value) = kind { return value <= 1 }
        return false
    }

    /// 通知标题（三类文案）
    public func title(providerName: String) -> String {
        switch kind {
        case .threshold:
            return "\(providerName) · \(resourceTitle)额度\(isCritical ? "即将用尽" : "偏低")"
        case .windowReset:
            return "\(providerName) · \(windowTitle ?? resourceTitle)额度已重置"
        case .balanceRecovered:
            return "\(providerName) · \(resourceTitle)额度已恢复"
        }
    }

    /// 通知正文
    ///
    /// 阈值：`剩余 3.74%，10/19 08:00 重置`
    /// 重置：`已恢复至 100%，下次重置 11/20 08:00`
    /// 回升：`剩余 3.2% → 18.6%（+15.4 个百分点）`
    public var bodyText: String {
        switch kind {
        case .threshold:
            let percent = formatExactNumber(max(0, remainingPercent))
            if let resetAt {
                return "剩余 \(percent)%，\(formatShortDateTime(resetAt)) 重置"
            }
            return "剩余 \(percent)%"
        case .windowReset:
            let percent = formatExactNumber(max(0, remainingPercent))
            if let resetAt {
                return "已恢复至 \(percent)%，下次重置 \(formatShortDateTime(resetAt))"
            }
            return "已恢复至 \(percent)%"
        case .balanceRecovered:
            let delta = recoveredPercent ?? 0
            let previous = max(0, remainingPercent - delta)
            return "剩余 \(formatExactNumber(previous))% → \(formatExactNumber(max(0, remainingPercent)))%"
                + "（+\(formatExactNumber(delta)) 个百分点）"
        }
    }
}

// MARK: - 评估器

/// 额度提醒评估器 — 输入余额快照与已提醒状态，输出本次应发提醒与更新后的状态
///
/// 规则：
/// - 每个额度资源（内含额度 / 每个百分比限额）独立记录，键为 `providerID.resourceID`
/// - 阈值：同一阈值在同一周期内只提醒一次；跌破更低阈值（5% → 4%）再提醒一次
/// - 重置：窗口进入新周期时提醒一次（同一 `cycleID` 不重复），并把已提醒阈值归零
/// - 回升：相邻两次观测的剩余比例上升达到阈值时提醒一次（有冷却）
/// - 重置当轮不再额外发回升提醒：重置文案已经表达「额度恢复」，两条同时到只会吵
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

            // 1) 周期重置（同一周期只发一次；有窗口按窗口判，无窗口按重置时刻判）
            let didReset = BillingRecoveryRule.isReset(previousState: previous, window: window, resetAt: resetAt)
            let cycleID = window?.cycleID ?? resetAt.map { formatter.string(from: $0) }
            if didReset, options.notifyWindowReset,
               BillingRecoveryRule.shouldNotifyReset(previousState: current, cycleID: cycleID) {
                alerts.append(BillingAlert(key: key, providerID: providerID, resourceTitle: title,
                                           kind: .windowReset, remainingPercent: fraction * 100,
                                           recoveredPercent: nil, windowTitle: window?.title ?? title,
                                           resetAt: resetAt))
                current.lastResetNotifiedCycleID = cycleID
            }

            // 2) 余额回升（重置当轮跳过；有冷却）
            if !didReset, options.notifyRecovery,
               BillingRecoveryRule.isCooldownElapsed(lastNotifiedAt: current.lastRecoveryNotifiedAt,
                                                     now: now, cooldown: options.recoveryCooldown) {
                let recovered = BillingRecoveryRule.recoveredPercent(from: previous?.lastRemainingFraction,
                                                                     to: fraction)
                if BillingRecoveryRule.shouldNotifyRecovery(recoveredPercent: recovered,
                                                            minimumPercent: options.recoveryMinimumPercent) {
                    alerts.append(BillingAlert(key: key, providerID: providerID, resourceTitle: title,
                                               kind: .balanceRecovered, remainingPercent: fraction * 100,
                                               recoveredPercent: recovered,
                                               windowTitle: window?.title, resetAt: resetAt))
                    current.lastRecoveryNotifiedAt = now
                }
            }

            // 3) 阈值（周期变化 / 重置后重新计数）
            if cycleID != current.cycleID || didReset {
                current.notifiedThreshold = 0
            }
            current.cycleID = cycleID
            if let threshold = BillingAlertThresholds.reachedThreshold(remainingFraction: fraction) {
                if options.notifyThresholds,
                   current.notifiedThreshold == 0 || threshold < current.notifiedThreshold {
                    alerts.append(BillingAlert(key: key, providerID: providerID, resourceTitle: title,
                                               kind: .threshold(threshold),
                                               remainingPercent: fraction * 100,
                                               recoveredPercent: nil, windowTitle: window?.title,
                                               resetAt: resetAt))
                    current.notifiedThreshold = threshold
                }
            } else if current.notifiedThreshold != 0 {
                // 回升到 5% 以上：清空已提醒记录，下次下降可再次提醒
                current.notifiedThreshold = 0
            }

            // 4) 刷新观测基线（重置 / 回升判定的输入）
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
