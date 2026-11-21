import Foundation

// MARK: - DeepSeek 余额响应

/// DeepSeek 余额响应 —— 官方文档：https://api-docs.deepseek.com/api/get-user-balance/
///
/// 响应形态（2026-11 官方文档）：
/// {
///   "is_available": true,
///   "balance_infos": [
///     { "currency": "CNY", "total_balance": "110.00",
///       "granted_balance": "10.00", "topped_up_balance": "100.00" }
///   ]
/// }
/// 金额字段是**字符串**（不是数字），解析失败必须报解析错误，不能静默按 0 处理。
public struct DeepSeekBalanceResponse: Decodable, Sendable {

    /// 每种币种一条余额（账户通常只有一条；多币种时优先 USD）
    public struct BalanceInfo: Decodable, Sendable {
        public let currency: String?
        public let totalBalance: String?
        public let grantedBalance: String?
        public let toppedUpBalance: String?

        enum CodingKeys: String, CodingKey {
            case currency
            case totalBalance = "total_balance"
            case grantedBalance = "granted_balance"
            case toppedUpBalance = "topped_up_balance"
        }
    }

    public let isAvailable: Bool?
    public let balanceInfos: [BalanceInfo]?

    enum CodingKeys: String, CodingKey {
        case isAvailable = "is_available"
        case balanceInfos = "balance_infos"
    }
}

// MARK: - 解码

/// DeepSeek 响应 → 通用余额模型
public enum DeepSeekBillingDecoding {

    /// 解析余额响应（余额 = `total_balance`，币种原样带出）
    public static func decodeBalance(from data: Data) throws -> BillingBalance {
        let dto: DeepSeekBalanceResponse
        do {
            dto = try JSONDecoder().decode(DeepSeekBalanceResponse.self, from: data)
        } catch {
            throw BillingError.invalidResponse(error.localizedDescription)
        }
        let infos = dto.balanceInfos ?? []
        guard !infos.isEmpty else {
            throw BillingError.invalidResponse("响应里没有 balance_infos")
        }
        // 多币种账户优先取美元，否则取第一条（官方文档只保证按币种分条）
        let info = infos.first { ($0.currency ?? "").uppercased() == "USD" } ?? infos[0]
        guard let total = amount(info.totalBalance) else {
            throw BillingError.invalidResponse("total_balance 无法解析")
        }
        return BillingBalance(purchasedUSD: total,
                              currencyCode: (info.currency ?? "USD").uppercased())
    }

    /// 字符串金额 → Double（空串 / 非法值 / NaN 一律 nil，由调用方转成解析错误）
    static func amount(_ raw: String?) -> Double? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(trimmed), value.isFinite else { return nil }
        return value
    }

    // MARK: - 错误映射

    /// HTTP 状态码 → 错误语义（401/403 凭据无效、429 频率限制、5xx 服务端错误、解析失败明确报错）
    public static func mapHTTPError(statusCode: Int, retryAfter: TimeInterval?,
                                    message: String?) -> BillingError {
        BillingHTTPErrorMapper.map(statusCode: statusCode, retryAfter: retryAfter,
                                   message: message,
                                   forbidden: .fixed("该 API Key 无权读取余额"))
    }
}
