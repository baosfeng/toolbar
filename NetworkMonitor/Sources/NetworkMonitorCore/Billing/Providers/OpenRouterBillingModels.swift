import Foundation

// MARK: - OpenRouter Key 额度响应

/// OpenRouter Key 额度响应 —— 官方文档：https://openrouter.ai/docs/api-reference/limits
///
/// 端点：GET https://openrouter.ai/api/v1/key（Bearer 认证，普通 API Key 即可）
/// 响应形态：
/// { "data": { "label": "sk-or-...", "limit": 100, "limit_remaining": 42.5,
///             "limit_reset": "monthly", "usage": 57.5, "is_free_tier": false } }
///
/// - `limit` 为 null 表示该 Key 没有额度上限（按量计费 / 无限制）
/// - 余额 = `limit_remaining`（缺失时用 `limit - usage` 兜底）
public struct OpenRouterKeyResponse: Decodable, Sendable {

    /// Key 详情
    public struct KeyInfo: Decodable, Sendable {
        public let label: String?
        public let limit: Double?
        public let limitRemaining: Double?
        public let limitReset: String?
        public let usage: Double?

        enum CodingKeys: String, CodingKey {
            case label
            case limit
            case limitRemaining = "limit_remaining"
            case limitReset = "limit_reset"
            case usage
        }
    }

    public let data: KeyInfo?
}

// MARK: - 解码

/// OpenRouter 响应 → 通用余额模型
public enum OpenRouterBillingDecoding {

    /// 无上限时的角标文案（沿用订阅型 provider「无限制」口径）
    public static let unlimitedBadge = "无限制"

    /// 解析 Key 额度响应
    ///
    /// 有上限 → 金额卡（剩余额度）；无上限 → 一条「无限制」的百分比卡。
    public static func decodeBalance(from data: Data) throws -> BillingBalance {
        let dto: OpenRouterKeyResponse
        do {
            dto = try JSONDecoder().decode(OpenRouterKeyResponse.self, from: data)
        } catch {
            throw BillingError.invalidResponse(error.localizedDescription)
        }
        guard let key = dto.data else {
            throw BillingError.invalidResponse("响应里没有 data")
        }
        guard let limit = key.limit else {
            // 没有上限即没有「余额」概念：给一条无限制额度行，UI 有内容可显示
            return BillingBalance(percentLimits: [
                BillingPercentLimit(id: "key-limit", title: "Key 额度",
                                    remainingFraction: 1, resetsAt: nil,
                                    badge: unlimitedBadge)
            ])
        }
        guard limit.isFinite, limit >= 0 else {
            throw BillingError.invalidResponse("limit 不是有效数字")
        }
        let remaining = key.limitRemaining ?? (limit - (key.usage ?? 0))
        guard remaining.isFinite else {
            throw BillingError.invalidResponse("limit_remaining 不是有效数字")
        }
        return BillingBalance(purchasedUSD: max(remaining, 0), currencyCode: "USD")
    }

    // MARK: - 错误映射

    /// HTTP 状态码 → 错误语义（401/403 凭据无效、429 频率限制、5xx 服务端错误、解析失败明确报错）
    public static func mapHTTPError(statusCode: Int, retryAfter: TimeInterval?,
                                    message: String?) -> BillingError {
        BillingHTTPErrorMapper.map(statusCode: statusCode, retryAfter: retryAfter,
                                   message: message,
                                   forbiddenMessage: "该 API Key 无权读取余额")
    }
}
