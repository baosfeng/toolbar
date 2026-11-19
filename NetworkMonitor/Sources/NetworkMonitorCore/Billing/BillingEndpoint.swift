import Foundation

// MARK: - 额度 GET 端点

/// 额度查询的 GET Endpoint 工厂 —— 9 家 provider 共用同一套头与错误映射装配
///
/// 只收敛「怎么发、怎么把状态码翻成 BillingError」，话术仍由 provider 自己的
/// `XxxBillingDecoding.mapHTTPError` 决定（各家 403 文案不同）。
public enum BillingEndpoint {

    /// - Parameters:
    ///   - headers: 业务头（Authorization / Cookie / Origin / Referer）
    ///   - userAgent: UA（nil = 不发，保持历史行为；App 侧 6 家在 BillingHTTPClient 里统一补）
    ///   - label: 日志里的 provider 名
    ///   - errorText: 错误体文案提取（默认通用四段，与改造前 BillingHTTPClient 同口径）
    ///   - status: 状态码 → 领域错误（provider 自己的 mapper；nil 走通用口径）
    public static func get(url: URL,
                           headers: [String: String],
                           userAgent: String? = nil,
                           timeout: TimeInterval = HTTPTransportDefaults.timeout,
                           label: String,
                           errorText: @escaping @Sendable (Data) -> String? = HTTPErrorBody.genericMessage(from:),
                           status: (@Sendable (Int, TimeInterval?, String?) -> BillingError)? = nil) -> Endpoint<Data> {
        Endpoint<Data>(method: .get,
                       url: url,
                       headers: headers,
                       userAgent: userAgent,
                       timeout: timeout,
                       label: label,
                       decoder: { $0 },
                       errorMapper: { failure in
                           BillingHTTPMapper.billing(failure, errorText: errorText, status: status)
                       })
    }
}
