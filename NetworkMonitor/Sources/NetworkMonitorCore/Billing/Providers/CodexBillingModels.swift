import Foundation

// MARK: - Codex（OpenAI 订阅额度）响应

/// 单个窗口快照 —— `used_percent` 已用百分比，`limit_window_seconds` 窗口时长，
/// `reset_at` 为 epoch 秒（`reset_after_seconds` 为相对秒数，仅在缺 `reset_at` 时使用）
struct CodexWindowDTO: Decodable {
    let usedPercent: Double?
    let limitWindowSeconds: TimeInterval?
    let resetAfterSeconds: TimeInterval?
    let resetAt: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case limitWindowSeconds = "limit_window_seconds"
        case resetAfterSeconds = "reset_after_seconds"
        case resetAt = "reset_at"
    }
}

/// 主 / 次窗口（5 小时会话 + 每周）
struct CodexRateLimitDTO: Decodable {
    let allowed: Bool?
    let limitReached: Bool?
    let primaryWindow: CodexWindowDTO?
    let secondaryWindow: CodexWindowDTO?

    enum CodingKeys: String, CodingKey {
        case allowed
        case limitReached = "limit_reached"
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }
}

/// 模型专属附加限额（如 Codex Spark）
struct CodexAdditionalLimitDTO: Decodable {
    let limitName: String?
    let primaryWindow: CodexWindowDTO?

    enum CodingKeys: String, CodingKey {
        case limitName = "limit_name"
        case primaryWindow = "primary_window"
    }
}

/// `GET https://chatgpt.com/backend-api/wham/usage` 响应（非公开端点）
struct CodexUsageResponseDTO: Decodable {
    let planType: String?
    let rateLimit: CodexRateLimitDTO?
    let additionalRateLimits: [CodexAdditionalLimitDTO]?

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
        case additionalRateLimits = "additional_rate_limits"
    }
}

// MARK: - 解码

/// Codex 额度解码 —— 纯函数，供 provider 与 TestRunner 共用
///
/// 接口形态来自 openai/codex 仓库的 codex-backend OpenAPI 生成模型
/// （`RateLimitStatusPayload` / `RateLimitWindowSnapshot`）。
public enum CodexBillingDecoding {

    /// 限流角标
    public static let rateLimitedBadge = "已限流"

    /// 解析额度响应
    ///
    /// - Parameter now: 当前时刻（`reset_after_seconds` 相对秒数的基准；缺 `reset_at` 时使用）
    public static func decodeBalance(from data: Data, now: Date = Date()) throws -> BillingBalance {
        guard let dto = try? JSONDecoder().decode(CodexUsageResponseDTO.self, from: data) else {
            throw BillingError.invalidResponse("响应不是合法的 Codex 额度 JSON（接口可能已变更）")
        }
        guard let rateLimit = dto.rateLimit else {
            throw BillingError.invalidResponse("响应里没有额度窗口（接口可能已变更）")
        }
        let limited = rateLimit.limitReached == true
        var limits: [BillingPercentLimit] = []
        if let limit = windowLimit(raw: rateLimit.primaryWindow, id: "codex-session",
                                   fallbackTitle: "5 小时", isLimited: limited, now: now) {
            limits.append(limit)
        }
        if let limit = windowLimit(raw: rateLimit.secondaryWindow, id: "codex-weekly",
                                   fallbackTitle: "每周", isLimited: limited, now: now) {
            limits.append(limit)
        }
        for (index, extra) in (dto.additionalRateLimits ?? []).enumerated() {
            let name = extra.limitName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let id = "codex-extra-" + (name.map(slug) ?? "limit-\(index)")
            let title = name.map { "\($0)" } ?? "附加限额"
            if let limit = windowLimit(raw: extra.primaryWindow, id: id, fallbackTitle: title,
                                       isLimited: limited, now: now) {
                limits.append(limit)
            }
        }
        guard !limits.isEmpty else {
            throw BillingError.invalidResponse("响应里没有额度窗口（接口可能已变更）")
        }
        return BillingBalance(percentLimits: limits)
    }

    /// 单窗口映射：已用百分比 → 剩余比例；限流时强制归零并加角标
    static func windowLimit(raw: CodexWindowDTO?, id: String, fallbackTitle: String,
                            isLimited: Bool, now: Date) -> BillingPercentLimit? {
        guard let raw, let used = raw.usedPercent else { return nil }
        let duration = raw.limitWindowSeconds ?? 0
        let window = duration > 0 ? resetWindow(raw: raw, duration: duration, now: now) : nil
        let title = window?.title ?? fallbackTitle
        return BillingPercentLimit(
            id: id,
            title: title,
            remainingFraction: isLimited ? 0 : BillingPercentMath.remainingFraction(usedPercent: used),
            resetsAt: window?.resetsAt ?? resetDate(raw: raw, now: now),
            badge: isLimited ? rateLimitedBadge : nil,
            window: window)
    }

    /// 窗口信息：优先 `reset_at`（epoch 秒），否则用 `reset_after_seconds` 相对 now 换算
    static func resetWindow(raw: CodexWindowDTO, duration: TimeInterval, now: Date) -> BillingQuotaWindow? {
        guard let resetsAt = resetDate(raw: raw, now: now) else { return nil }
        return BillingQuotaWindow(kind: BillingQuotaWindow.kind(forDuration: duration),
                                  duration: duration,
                                  resetsAt: resetsAt)
    }

    /// 重置时刻
    static func resetDate(raw: CodexWindowDTO, now: Date) -> Date? {
        if let date = BillingISO8601.date(epochSeconds: raw.resetAt) { return date }
        guard let seconds = raw.resetAfterSeconds, seconds > 0 else { return nil }
        return now.addingTimeInterval(seconds)
    }

    /// 名称转 slug（附加限额 id 用）
    static func slug(_ raw: String) -> String {
        raw.lowercased()
            .map { ($0.isLetter && $0.isASCII) || $0.isNumber ? $0 : "-" }
            .reduce(into: "") { result, char in
                if char == "-", result.last == "-" { return }
                result.append(char)
            }
    }

    /// HTTP 状态码 → 领域错误
    public static func mapHTTPError(statusCode: Int, retryAfter: TimeInterval?,
                                    message: String?) -> BillingError {
        switch statusCode {
        case 400:
            return .invalidRequest(message ?? "请求参数有误（接口可能已变更）")
        case 401:
            return .unauthorized
        case 403:
            return .forbidden("凭据已失效或该账号无权读取 Codex 用量，请重新登录后更新 token")
        case 429:
            return .rateLimited(retryAfter: retryAfter)
        case 500...599:
            return .serviceUnavailable(message)
        default:
            return .invalidResponse("HTTP \(statusCode)")
        }
    }
}
