import Foundation

// MARK: - 提醒种类

/// 提醒种类 —— 文案与去重口径都按种类区分
///
/// 「用尽」是唯一的低额度硬信号：剩余跌破用尽线时提醒一次，同一周期不再重发。
/// 「偏低」只做预告（5% / 4% / 3% / 2%），同一周期发过用尽后不再单独发更低档。
/// 「恢复」只出现在**本周期曾用尽**的额度上：没用尽过的额度切多少轮窗口周期都静默。
public enum BillingAlertKind: Sendable, Equatable {
    /// 额度用尽（剩余跌破用尽线）
    case exhausted
    /// 剩余跌破阈值（偏低预告）
    case threshold(Int)
    /// 曾用尽的额度恢复（窗口切周期 / 剩余回到用尽线以上）
    case recovered
    /// 余额回升（相邻两次观测上升达到阈值；带冷却，与恢复是两条独立信号）
    case balanceRecovered
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
    /// 回升百分点（仅「额度回升」有值）
    public let recoveredPercent: Double?
    /// 窗口展示名（会话窗口按时长给「5 小时」，周 / 月窗口给「每周」「每月」）
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

    /// 命中的阈值（非阈值类为 0）
    public var threshold: Int {
        if case .threshold(let value) = kind { return value }
        return 0
    }

    /// 窗口展示名：优先窗口标题，无窗口信息时回退到额度行标题
    public var windowLabel: String { windowTitle ?? resourceTitle }

    /// 通知标题
    ///
    /// 用尽 / 恢复带窗口名（「5 小时」「每周」），用户一眼看出是哪一份额度；
    /// 没有窗口信息的 provider 回退到额度行标题。
    public func title(providerName: String) -> String {
        switch kind {
        case .exhausted:
            return "\(providerName) · \(windowLabel)额度已用尽"
        case .threshold:
            return "\(providerName) · \(resourceTitle)额度偏低"
        case .recovered:
            return "\(providerName) · \(windowLabel)额度已恢复"
        case .balanceRecovered:
            return "\(providerName) · \(resourceTitle)额度回升"
        }
    }

    /// 通知正文
    ///
    /// 用尽：`剩余 0.4%，11/15 20:00 重置`
    /// 阈值：`剩余 3.74%，10/19 08:00 重置`
    /// 恢复：`已恢复至 100%，下次重置 11/20 08:00`
    /// 回升：`剩余 3.2% → 18.6%（+15.4 个百分点）`
    public var bodyText: String {
        switch kind {
        case .exhausted:
            let percent = formatExactNumber(max(0, remainingPercent))
            guard let resetAt else { return "剩余 \(percent)%" }
            return "剩余 \(percent)%，\(formatShortDateTime(resetAt)) 重置"
        case .threshold:
            let percent = formatExactNumber(max(0, remainingPercent))
            guard let resetAt else { return "剩余 \(percent)%" }
            return "剩余 \(percent)%，\(formatShortDateTime(resetAt)) 重置"
        case .recovered:
            let percent = formatExactNumber(max(0, remainingPercent))
            guard let resetAt else { return "已恢复至 \(percent)%" }
            return "已恢复至 \(percent)%，下次重置 \(formatShortDateTime(resetAt))"
        case .balanceRecovered:
            let delta = recoveredPercent ?? 0
            let previous = max(0, remainingPercent - delta)
            return "剩余 \(formatExactNumber(previous))% → \(formatExactNumber(max(0, remainingPercent)))%"
                + "（+\(formatExactNumber(delta)) 个百分点）"
        }
    }
}

// MARK: - 折叠成待发送通知

/// 一条折叠好的通知 —— 种类决定它落到事件表的哪一行
public struct BillingAlertMessage: Sendable, Equatable {
    public let kind: BillingAlertKind
    public let title: String
    public let body: String

    public init(kind: BillingAlertKind, title: String, body: String) {
        self.kind = kind
        self.title = title
        self.body = body
    }
}

/// 把一次评估产出的提醒折叠成实际要发的通知
///
/// 用尽与恢复各合成一条：同一 provider 的「5 小时」与「每周」同时用尽时只弹一次窗，
/// 正文列出这两个窗口名与各自剩余，不连发多条弹窗。
/// 阈值与回升保留逐条 —— 它们的信息在具体数值上，合并反而丢细节。
public enum BillingAlertDigest {

    /// 折叠顺序：用尽 → 恢复 → 其余逐条（用尽是最硬信号，排最前）
    public static func messages(for alerts: [BillingAlert],
                               providerName: String) -> [BillingAlertMessage] {
        var messages: [BillingAlertMessage] = []
        if let message = merged(alerts.filter { $0.kind == .exhausted },
                                providerName: providerName, tail: "已用尽", percentPrefix: "剩余 ") {
            messages.append(message)
        }
        if let message = merged(alerts.filter { $0.kind == .recovered },
                                providerName: providerName, tail: "已恢复", percentPrefix: "") {
            messages.append(message)
        }
        for alert in alerts where alert.kind != .exhausted && alert.kind != .recovered {
            messages.append(BillingAlertMessage(kind: alert.kind,
                                                title: alert.title(providerName: providerName),
                                                body: alert.bodyText))
        }
        return messages
    }

    /// 同类多条合并成一条；只有一条时沿用该条自己的窗口文案
    private static func merged(_ alerts: [BillingAlert], providerName: String,
                               tail: String, percentPrefix: String) -> BillingAlertMessage? {
        guard let first = alerts.first else { return nil }
        guard alerts.count > 1 else {
            return BillingAlertMessage(kind: first.kind,
                                       title: first.title(providerName: providerName),
                                       body: first.bodyText)
        }
        let names = alerts.map(\.windowLabel).joined(separator: "、")
        let percents = alerts.map { formatExactNumber(max(0, $0.remainingPercent)) + "%" }
            .joined(separator: " / ")
        return BillingAlertMessage(kind: first.kind,
                                   title: "\(providerName) · 额度\(tail)",
                                   body: "\(names)均\(tail)（\(percentPrefix)\(percents)）")
    }
}
