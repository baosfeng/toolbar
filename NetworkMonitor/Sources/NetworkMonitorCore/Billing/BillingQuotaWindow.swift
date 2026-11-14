import Foundation

// MARK: - 额度窗口

/// 额度窗口种类 —— 订阅类 provider（Claude / Codex / Cursor）都按「窗口」计量，
/// 窗口种类决定通知文案（「会话已重置」/「周额度已重置」/「月度已重置」）
public enum BillingWindowKind: String, Sendable, Equatable, Codable, CaseIterable {
    /// 短会话窗口（Claude 5 小时 / Codex 5 小时）
    case session
    case daily
    case weekly
    case monthly
    case custom

    /// 展示名（额度卡行标题后缀 / 通知文案）
    public var title: String {
        switch self {
        case .session: return "会话"
        case .daily: return "每日"
        case .weekly: return "每周"
        case .monthly: return "每月"
        case .custom: return "自定义"
        }
    }
}

/// 额度窗口 —— 种类 + 时长 + 下次重置时刻
///
/// 恢复通知需要「同一窗口的相邻两次观测」，因此窗口必须带稳定周期标识 `cycleID`：
/// 重置时刻前进即视为新周期，reminder 只在周期切换时触发一次。
public struct BillingQuotaWindow: Sendable, Equatable, Codable {
    /// 窗口种类
    public let kind: BillingWindowKind
    /// 窗口时长（秒；服务端给 `limit_window_seconds` 时直接用，否则按账单周期推算）
    public let duration: TimeInterval
    /// 下次重置时刻
    public let resetsAt: Date

    public init(kind: BillingWindowKind, duration: TimeInterval, resetsAt: Date) {
        self.kind = kind
        self.duration = duration
        self.resetsAt = resetsAt
    }

    /// 周期稳定标识（同一重置时刻 = 同一周期）
    public var cycleID: String { "\(kind.rawValue)@\(Int(resetsAt.timeIntervalSince1970))" }

    /// 按窗口秒数推断种类（服务端给的 `limit_window_seconds` 是权威值）
    public static func kind(forDuration seconds: TimeInterval) -> BillingWindowKind {
        // 分档按「服务端实际会给出的窗口」取：5 小时 = 18000、日 = 86400、周 = 604800、月 ≈ 2592000
        switch seconds {
        case ..<21_600: return .session          // ≤ 6 小时（会话窗口）
        case 21_600..<129_600: return .daily     // ≤ 36 小时
        case 129_600..<1_728_000: return .weekly // ≤ 20 天
        case 1_728_000..<3_456_000: return .monthly
        default: return .custom
        }
    }

    /// 展示标题：优先「每周 / 每月」这类固定名，其余回退到小时 / 天
    public var title: String {
        switch kind {
        case .session:
            let hours = duration / 3_600
            return hours >= 1 ? "\(Int(hours.rounded())) 小时" : "会话"
        case .daily, .weekly, .monthly:
            return kind.title
        case .custom:
            let days = duration / 86_400
            return days >= 1 ? "\(Int(days.rounded())) 天" : kind.title
        }
    }

    /// 便捷构造：从服务端秒数 + 重置时刻生成
    public static func make(duration: TimeInterval, resetsAt: Date) -> BillingQuotaWindow {
        BillingQuotaWindow(kind: kind(forDuration: duration), duration: duration, resetsAt: resetsAt)
    }
}
