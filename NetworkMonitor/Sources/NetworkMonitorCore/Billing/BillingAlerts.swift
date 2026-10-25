import Foundation

// MARK: - 额度阈值提醒（纯逻辑）

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

/// 单个额度的提醒状态（持久化到偏好）
public struct BillingAlertState: Codable, Sendable, Equatable {
    /// 周期标识（重置时间 ISO 值；nil = 服务端未给周期）
    public var cycleID: String?
    /// 已提醒过的阈值（0 = 尚未提醒）
    public var notifiedThreshold: Int

    public init(cycleID: String? = nil, notifiedThreshold: Int = 0) {
        self.cycleID = cycleID
        self.notifiedThreshold = notifiedThreshold
    }
}

/// 一条待发送的提醒
public struct BillingAlert: Sendable, Equatable {
    /// 状态键（providerID.resourceID）
    public let key: String
    public let providerID: String
    /// 额度名称（会话 / 每周 / 内含）
    public let resourceTitle: String
    /// 命中的阈值（5...1）
    public let threshold: Int
    /// 实际剩余百分比（服务端原值，不取整）
    public let remainingPercent: Double
    /// 下次重置时间
    public let resetAt: Date?

    public init(key: String, providerID: String, resourceTitle: String,
                threshold: Int, remainingPercent: Double, resetAt: Date?) {
        self.key = key
        self.providerID = providerID
        self.resourceTitle = resourceTitle
        self.threshold = threshold
        self.remainingPercent = remainingPercent
        self.resetAt = resetAt
    }

    /// 是否「即将用尽」档（1%）
    public var isCritical: Bool { threshold <= 1 }

    /// 通知标题（分级）：`Ollama · 会话额度偏低` / `Ollama · 内含额度即将用尽`
    public func title(providerName: String) -> String {
        "\(providerName) · \(resourceTitle)额度\(isCritical ? "即将用尽" : "偏低")"
    }

    /// 通知正文：`剩余 3.74%，10/19 08:00 重置`（无周期时省略后半句）
    ///
    /// 百分比按服务端原值展示，与额度页一致，不取整成整数。
    public var bodyText: String {
        let percent = formatExactNumber(max(0, remainingPercent))
        if let resetAt {
            return "剩余 \(percent)%，\(formatShortDateTime(resetAt)) 重置"
        }
        return "剩余 \(percent)%"
    }
}

// MARK: - 评估器

/// 额度提醒评估器 — 输入余额快照与已提醒状态，输出本次应发提醒与更新后的状态
///
/// 规则：
/// - 每个额度资源（内含额度 / 每个百分比限额）独立记录，键为 `providerID.resourceID`
/// - 同一阈值在同一周期内只提醒一次；跌破更低阈值（5% → 4%）再提醒一次
/// - 周期变化（重置时间改变）或余额回升到 5% 以上时，清空已提醒记录
public enum BillingAlertEvaluator {

    /// 评估一次余额快照
    public static func evaluate(balance: BillingBalance,
                                providerID: String,
                                state: [String: BillingAlertState]) -> (alerts: [BillingAlert], state: [String: BillingAlertState]) {
        var alerts: [BillingAlert] = []
        var updated = state
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        func consider(resourceID: String, title: String, fraction: Double,
                      cycleID: String?, resetAt: Date?) {
            let key = "\(providerID).\(resourceID)"
            let previous = state[key]
            // 周期变化：重新开始记录
            var current = BillingAlertState(cycleID: cycleID)
            if let previous, previous.cycleID == cycleID {
                current.notifiedThreshold = previous.notifiedThreshold
            }

            guard let threshold = BillingAlertThresholds.reachedThreshold(remainingFraction: fraction) else {
                // 回升到 5% 以上：清空记录，下次下降可再次提醒
                if current.notifiedThreshold != 0 {
                    current.notifiedThreshold = 0
                    updated[key] = current
                }
                return
            }
            if current.notifiedThreshold == 0 || threshold < current.notifiedThreshold {
                alerts.append(BillingAlert(key: key,
                                           providerID: providerID,
                                           resourceTitle: title,
                                           threshold: threshold,
                                           remainingPercent: fraction * 100,
                                           resetAt: resetAt))
                current.notifiedThreshold = threshold
            }
            updated[key] = current
        }

        if let included = balance.included {
            consider(resourceID: "included",
                     title: "内含",
                     fraction: included.remainingFraction,
                     cycleID: included.period.map { formatter.string(from: $0.end) },
                     resetAt: included.period?.end)
        }
        for limit in balance.percentLimits {
            consider(resourceID: limit.id,
                     title: limit.title,
                     fraction: limit.remainingFraction,
                     cycleID: limit.resetsAt.map { formatter.string(from: $0) },
                     resetAt: limit.resetsAt)
        }
        return (alerts, updated)
    }
}
