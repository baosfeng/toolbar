import Foundation

// MARK: - 失败 → BillingError

/// 传输层失败 → 额度领域错误 —— Core 侧 9 家 provider 共用
///
/// 收敛的只是「状态码 → 错误类别」这一步；各家 403 / 400 的用户话术仍由 provider
/// 通过参数给出（Claude 说 OAuth token、Cursor 说 Cookie、OpenCode Go 说没订阅）。
public enum BillingHTTPMapper {

    /// 拼请求地址 —— 失败文案与改造前一致（provider 各自原来都写了两句中文）
    ///
    /// - Note: 用 typed throws（SE-0413）把错误域收到 `BillingError`。上游 `HTTPURLBuilder.url`
    ///   已声明封闭的 `Failure`，所以这里的 `switch` 是穷举的——原来兜底的 `catch`（猜它是
    ///   「请求地址无效」）已删掉，新增失败种类时编译器会直接要求补分支。
    public static func url(base: URL, path: String, query: [(String, String)] = []) throws(BillingError) -> URL {
        do {
            return try HTTPURLBuilder.url(base: base, path: path, query: query)
        } catch {
            switch error {
            case .invalidBase:
                throw BillingError.invalidRequest("无效的 provider 地址")
            case .invalidURL:
                throw BillingError.invalidRequest("无效的请求地址")
            }
        }
    }

    /// - Parameters:
    ///   - forbidden: 403 的话术口径（默认透传错误体文案）
    ///   - badRequestFallback: 400 且错误体没文案时的兜底话术（nil 时与通用口径一致）
    ///   - errorText: 错误体文案提取口径（各家后端形态不同，默认取通用四段）
    ///   - status: 状态码 → 领域错误（provider 自己的 mapper；nil 时走 BillingHTTPErrorMapper 通用口径）
    public static func billing(_ failure: HTTPFailure,
                               forbidden: BillingHTTPErrorMapper.ForbiddenText = .serverText,
                               badRequestFallback: String? = nil,
                               errorText: @escaping @Sendable (Data) -> String? = HTTPErrorBody.genericMessage(from:),
                               status: (@Sendable (Int, TimeInterval?, String?) -> BillingError)? = nil) -> BillingError {
        switch failure {
        case .transport(let failure):
            return .transport(failure.message)
        case .notHTTP:
            return .invalidResponse("非 HTTP 响应")
        case .response(let response):
            let message = errorText(response.data) ?? response.message ?? badRequestFallback
            if let status {
                return status(response.statusCode, response.retryAfter, message)
            }
            return BillingHTTPErrorMapper.map(statusCode: response.statusCode,
                                               retryAfter: response.retryAfter,
                                               message: message,
                                               forbidden: forbidden)
        }
    }
}
