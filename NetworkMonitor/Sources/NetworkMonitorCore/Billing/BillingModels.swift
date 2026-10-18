import Foundation

// MARK: - 计费通用模型

/// 计费统计时间范围（与具体 provider 无关，各 provider 自行映射）
public enum BillingRange: String, CaseIterable, Sendable, Equatable {
    case last24Hours = "24h"
    case last7Days = "7d"
    case last30Days = "30d"

    /// 分段标题（UI 直接使用）
    public var title: String {
        switch self {
        case .last24Hours: return "24小时"
        case .last7Days: return "7天"
        case .last30Days: return "30天"
        }
    }

    /// 查询参数取值（provider 映射用）
    public var queryValue: String { rawValue }
}

/// 用量分桶粒度
public enum BillingGranularity: String, Sendable, Equatable {
    case hour
    case day
}

// MARK: - 额度（余额）

/// 计费周期（起止均按 provider 返回原值时区语义，UTC 时间点）
public struct BillingPeriod: Sendable, Equatable {
    public let start: Date
    public let end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    /// 周期总时长（秒）
    public var duration: TimeInterval { end.timeIntervalSince(start) }

    /// 周期进度 0...1（当前时间在周期内的位置）
    public func progress(at now: Date = Date()) -> Double {
        guard duration > 0 else { return 0 }
        return min(max(now.timeIntervalSince(start) / duration, 0), 1)
    }

    /// 距周期结束剩余天数（不足一天按 1 计，已结束返回 0）
    public func remainingDays(at now: Date = Date()) -> Int {
        let remaining = end.timeIntervalSince(now)
        guard remaining > 0 else { return 0 }
        return Int(ceil(remaining / 86_400))
    }
}

/// 套餐内含额度（如 Ollama 月度 allowance）
public struct BillingIncludedBalance: Sendable, Equatable {
    /// 剩余额度（美元）
    public let remainingUSD: Double
    /// 本周期总额度（美元）
    public let allowanceUSD: Double
    /// 计费周期（部分 provider 不返回）
    public let period: BillingPeriod?

    public init(remainingUSD: Double, allowanceUSD: Double, period: BillingPeriod? = nil) {
        self.remainingUSD = remainingUSD
        self.allowanceUSD = allowanceUSD
        self.period = period
    }

    /// 剩余比例 0...1（总额度非正时按 0 处理）
    public var remainingFraction: Double {
        guard allowanceUSD > 0 else { return 0 }
        return min(max(remainingUSD / allowanceUSD, 0), 1)
    }
}

/// 按百分比计量的限额（如 Ollama 遗留计划的 session / weekly）
public struct BillingPercentLimit: Sendable, Equatable {
    /// 稳定标识（session / weekly 等，用于 UI 排序与键）
    public let id: String
    /// 展示名称
    public let title: String
    /// 剩余比例 0...1
    public let remainingFraction: Double
    /// 下次重置时间
    public let resetsAt: Date?

    public init(id: String, title: String, remainingFraction: Double, resetsAt: Date?) {
        self.id = id
        self.title = title
        self.remainingFraction = min(max(remainingFraction, 0), 1)
        self.resetsAt = resetsAt
    }
}

/// 账户余额（各 provider 通用）
public struct BillingBalance: Sendable, Equatable {
    /// 套餐内含额度（nil = provider 不提供或未订阅）
    public let included: BillingIncludedBalance?
    /// 已购买额度余额（美元，nil = 无购买额度或 provider 不提供）
    public let purchasedUSD: Double?
    /// 百分比限额（遗留计划 / 会话限额）
    public let percentLimits: [BillingPercentLimit]

    public init(included: BillingIncludedBalance? = nil,
                purchasedUSD: Double? = nil,
                percentLimits: [BillingPercentLimit] = []) {
        self.included = included
        self.purchasedUSD = purchasedUSD
        self.percentLimits = percentLimits
    }

    /// 可用总额（美元）：内含剩余 + 已购买；两者都缺省时为 nil
    public var totalAvailableUSD: Double? {
        guard included != nil || purchasedUSD != nil else { return nil }
        return (included?.remainingUSD ?? 0) + (purchasedUSD ?? 0)
    }

    /// 是否为空余额（无任何额度信息，UI 用于空态判断）
    public var isEmpty: Bool {
        included == nil && purchasedUSD == nil && percentLimits.isEmpty
    }
}

// MARK: - 用量

/// 用量指标（请求数 / 金额 / token）
public struct BillingMetrics: Sendable, Equatable {
    public let requestCount: Int
    public let usageUSD: Double?
    public let inputTokens: Int?
    public let cachedInputTokens: Int?
    public let outputTokens: Int?

    public init(requestCount: Int = 0,
                usageUSD: Double? = nil,
                inputTokens: Int? = nil,
                cachedInputTokens: Int? = nil,
                outputTokens: Int? = nil) {
        self.requestCount = requestCount
        self.usageUSD = usageUSD
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
    }
}

/// 分组用量（模型 / API Key 等维度，由 provider 决定分组键语义）
public struct BillingGroup: Sendable, Equatable {
    /// 分组名（如模型名）
    public let name: String
    public let metrics: BillingMetrics

    public init(name: String, metrics: BillingMetrics) {
        self.name = name
        self.metrics = metrics
    }
}

/// 用量分桶（小时 / 天）
public struct BillingBucket: Sendable, Equatable {
    public let start: Date
    public let end: Date
    /// 该桶是否仍在累计中（当前小时 / 当天）
    public let isPartial: Bool
    public let metrics: BillingMetrics
    public let groups: [BillingGroup]

    public init(start: Date, end: Date, isPartial: Bool,
                metrics: BillingMetrics, groups: [BillingGroup] = []) {
        self.start = start
        self.end = end
        self.isPartial = isPartial
        self.metrics = metrics
        self.groups = groups
    }
}

/// 用量统计（含总量、分桶与分组明细）
public struct BillingUsage: Sendable, Equatable {
    public let range: BillingRange
    public let granularity: BillingGranularity
    public let start: Date
    public let end: Date
    public let totals: BillingMetrics
    public let buckets: [BillingBucket]
    public let groups: [BillingGroup]

    public init(range: BillingRange,
                granularity: BillingGranularity,
                start: Date,
                end: Date,
                totals: BillingMetrics,
                buckets: [BillingBucket],
                groups: [BillingGroup] = []) {
        self.range = range
        self.granularity = granularity
        self.start = start
        self.end = end
        self.totals = totals
        self.buckets = buckets
        self.groups = groups
    }
}
