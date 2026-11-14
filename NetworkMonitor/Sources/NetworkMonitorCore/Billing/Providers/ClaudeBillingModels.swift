import Foundation

// MARK: - Claude（Anthropic）订阅额度响应

/// 单个窗口 DTO —— `/api/oauth/usage` 里 `five_hour` / `seven_day*` 的统一结构
///
/// `utilization` 是**已用百分比**（0…100，脏数据可能越界）；`resets_at` 是 ISO8601 字符串。
struct ClaudeUsageWindowDTO: Decodable {
    let utilization: Double?
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

/// 额外用量（Extra usage）—— 月度花费上限
struct ClaudeExtraUsageDTO: Decodable {
    let isEnabled: Bool?
    let monthlyLimit: Double?
    let usedCredits: Double?
    let utilization: Double?
    let currency: String?

    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case monthlyLimit = "monthly_limit"
        case usedCredits = "used_credits"
        case utilization
        case currency
    }
}

/// `GET https://api.anthropic.com/api/oauth/usage` 响应（非公开端点）
struct ClaudeUsageResponseDTO: Decodable {
    let fiveHour: ClaudeUsageWindowDTO?
    let sevenDay: ClaudeUsageWindowDTO?
    let sevenDaySonnet: ClaudeUsageWindowDTO?
    let sevenDayOpus: ClaudeUsageWindowDTO?
    let extraUsage: ClaudeExtraUsageDTO?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDaySonnet = "seven_day_sonnet"
        case sevenDayOpus = "seven_day_opus"
        case extraUsage = "extra_usage"
    }
}

// MARK: - 解码

/// Claude 额度解码 —— 纯函数，供 provider 与 TestRunner 共用（离线可测）
///
/// 接口形态来自社区实现（CodexBar `ClaudeOAuthUsageFetcher`，非 Anthropic 公开文档）：
/// 字段缺失即视为该窗口不存在（Free 计划返回 null 的 `five_hour` / `seven_day`）。
public enum ClaudeBillingDecoding {

    /// 窗口白名单：键名 → (限额 id, 展示名, 窗口种类, 窗口时长)
    static let windowTable: [(key: String, id: String, title: String,
                              kind: BillingWindowKind, duration: TimeInterval)] = [
        ("five_hour", "claude-session", "5 小时", .session, 18_000),
        ("seven_day", "claude-weekly", "每周", .weekly, 604_800),
        ("seven_day_sonnet", "claude-weekly-sonnet", "每周 · Sonnet", .weekly, 604_800),
        ("seven_day_opus", "claude-weekly-opus", "每周 · Opus", .weekly, 604_800),
    ]

    /// 解析额度响应
    public static func decodeBalance(from data: Data) throws -> BillingBalance {
        guard let dto = try? JSONDecoder().decode(ClaudeUsageResponseDTO.self, from: data) else {
            throw BillingError.invalidResponse("响应不是合法的 Claude 额度 JSON（接口可能已变更）")
        }
        let windows: [String: ClaudeUsageWindowDTO?] = [
            "five_hour": dto.fiveHour,
            "seven_day": dto.sevenDay,
            "seven_day_sonnet": dto.sevenDaySonnet,
            "seven_day_opus": dto.sevenDayOpus,
        ]
        var limits: [BillingPercentLimit] = []
        for entry in windowTable {
            guard let raw = windows[entry.key] ?? nil, let used = raw.utilization else { continue }
            let resetAt = raw.resetsAt.flatMap(BillingISO8601.parse)
            limits.append(BillingPercentLimit(
                id: entry.id,
                title: entry.title,
                remainingFraction: BillingPercentMath.remainingFraction(usedPercent: used),
                resetsAt: resetAt,
                window: resetAt.map { BillingQuotaWindow(kind: entry.kind, duration: entry.duration, resetsAt: $0) }))
        }
        if let extra = limitsForExtraUsage(dto.extraUsage) { limits.append(extra) }
        guard !limits.isEmpty else {
            throw BillingError.invalidResponse("响应里没有额度窗口（可能是非订阅账号，或接口已变更）")
        }
        return BillingBalance(percentLimits: limits)
    }

    /// 额外用量窗口（仅当已启用且月度上限为正）
    static func limitsForExtraUsage(_ extra: ClaudeExtraUsageDTO?) -> BillingPercentLimit? {
        guard let extra, extra.isEnabled == true,
              let limit = extra.monthlyLimit, limit > 0,
              let used = extra.usedCredits else { return nil }
        return BillingPercentLimit(id: "claude-extra",
                                   title: "额外用量",
                                   remainingFraction: BillingPercentMath.remainingFraction(used: used, limit: limit),
                                   resetsAt: nil,
                                   usedAmount: used,
                                   limitAmount: limit,
                                   unitLabel: extra.currency ?? "credits")
    }

    /// HTTP 状态码 → 领域错误（401 / 403 给「凭据失效」类明确文案）
    public static func mapHTTPError(statusCode: Int, retryAfter: TimeInterval?,
                                    message: String?) -> BillingError {
        switch statusCode {
        case 400:
            return .invalidRequest(message ?? "请求参数有误（接口可能已变更）")
        case 401:
            return .unauthorized
        case 403:
            return .forbidden("凭据已失效或缺少 usage 权限，请更新 OAuth token")
        case 429:
            return .rateLimited(retryAfter: retryAfter)
        case 500...599:
            return .serviceUnavailable(message)
        default:
            return .invalidResponse("HTTP \(statusCode)")
        }
    }
}
