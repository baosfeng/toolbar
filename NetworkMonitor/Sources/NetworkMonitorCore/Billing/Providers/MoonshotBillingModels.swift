import Foundation

// MARK: - Moonshot / Kimi 开放平台余额响应

/// Moonshot（Kimi）开放平台余额响应
///
/// 官方文档：https://platform.moonshot.cn/docs/api/balance
/// 国内站 `https://api.moonshot.cn/v1/users/me/balance`，
/// 国际站 `https://api.moonshot.ai/v1/users/me/balance`（字段完全一致）。
///
/// 响应形态：
/// { "code": 0, "status": true,
///   "data": { "available_balance": 100, "voucher_balance": 10, "cash_balance": 90 } }
public struct MoonshotBalanceResponse: Decodable, Sendable {

    /// 余额三段（可用 / 代金券 / 现金）
    public struct Payload: Decodable, Sendable {
        public let availableBalance: Double?
        public let voucherBalance: Double?
        public let cashBalance: Double?

        enum CodingKeys: String, CodingKey {
            case availableBalance = "available_balance"
            case voucherBalance = "voucher_balance"
            case cashBalance = "cash_balance"
        }
    }

    public let code: Int?
    public let status: Bool?
    public let data: Payload?
}

// MARK: - 解码

/// Moonshot 响应 → 通用余额模型
public enum MoonshotBillingDecoding {

    /// 解析余额响应
    ///
    /// - Parameters:
    ///   - data: 原始响应体
    ///   - currencyCode: 站点本位币种（国内站 CNY、国际站 USD；接口本身不返回币种）
    public static func decodeBalance(from data: Data, currencyCode: String) throws -> BillingBalance {
        let dto: MoonshotBalanceResponse
        do {
            dto = try JSONDecoder().decode(MoonshotBalanceResponse.self, from: data)
        } catch {
            throw BillingError.invalidResponse(error.localizedDescription)
        }
        // HTTP 200 但业务码非 0：明确报错，不返回 0 余额
        if let code = dto.code, code != 0 {
            throw BillingError.invalidResponse("接口返回错误码 \(code)")
        }
        if dto.status == false {
            throw BillingError.invalidResponse("接口返回 status=false")
        }
        guard let payload = dto.data, let available = payload.availableBalance else {
            throw BillingError.invalidResponse("响应里没有 data.available_balance")
        }
        guard available.isFinite else {
            throw BillingError.invalidResponse("available_balance 不是有效数字")
        }
        return BillingBalance(purchasedUSD: available, currencyCode: currencyCode)
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
