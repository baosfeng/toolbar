import Foundation

// MARK: - 响应装箱

/// 一次 HTTP 响应 —— 数据 + 状态码 + 需要透出的响应头 + 提好的错误文案
///
/// 响应头透出是为了少数依赖头部的判定：GitHub 限流要看 X-RateLimit-Remaining，
/// 429 退避要看 Retry-After。除白名单键外其余头不保留（凭据头不留在内存里传播）。
public struct HTTPResponse: Sendable {
    /// 响应体
    public let data: Data
    /// HTTP 状态码
    public let statusCode: Int
    /// 响应头白名单（键小写）：retry-after / x-ratelimit-remaining / x-pair-key ...
    public let headers: [String: String]
    /// 服务端错误体里提取的可读文案（成功响应为 nil）
    public let message: String?

    public init(data: Data, statusCode: Int, headers: [String: String] = [:], message: String? = nil) {
        self.data = data
        self.statusCode = statusCode
        self.headers = headers
        self.message = message
    }

    /// 2xx 判定
    public var isSuccess: Bool { (200..<300).contains(statusCode) }

    /// Retry-After 秒数（解析失败 / 缺头为 nil）
    public var retryAfter: TimeInterval? {
        HTTPRetryAfter.parse(headers["retry-after"])
    }

    /// 取某个响应头（大小写不敏感：内部键统一小写）
    public func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }
}

// MARK: - Retry-After 解析

/// Retry-After 解析 —— 全仓唯一一份
///
/// 两种合法形态都收：秒数（"120"）与 HTTP 日期（"Wed, 21 Oct 2015 07:28:00 GMT"）。
/// 脏数据（负数 / 非数字 / 空串）一律当作「没给」，由调用方决定默认退避。
public enum HTTPRetryAfter {
    public static func parse(_ raw: String?) -> TimeInterval? {
        guard let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        if let seconds = Double(text) {
            return seconds >= 0 ? seconds : nil
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = formatter.date(from: text) else { return nil }
        return max(date.timeIntervalSinceNow, 0)
    }
}

// MARK: - 状态码 → 错误语义

/// 状态码的统一分级 —— 与业务无关，只分「参数 / 凭据 / 权限 / 频率 / 服务端」
///
/// 各 provider 的用户话术不同（403 尤其），所以这里只给分级与原始信息，
/// 话术由 provider 在自己的 errorMapper 里决定。
public enum HTTPStatusCode: Equatable, Sendable {
    /// 400
    case badRequest(String?)
    /// 401
    case unauthorized
    /// 403
    case forbidden(String?)
    /// 429（带 Retry-After）
    case rateLimited(retryAfter: TimeInterval?)
    /// 500...599
    case serverError(String?)
    /// 其余非 2xx
    case unexpected(Int)

    /// 统一映射 —— 全仓唯一一份状态码口径
    public static func map(_ statusCode: Int, retryAfter: TimeInterval?, message: String?) -> HTTPStatusCode {
        switch statusCode {
        case 400:
            return .badRequest(message)
        case 401:
            return .unauthorized
        case 403:
            return .forbidden(message)
        case 429:
            return .rateLimited(retryAfter: retryAfter)
        case 500...599:
            return .serverError(message)
        default:
            return .unexpected(statusCode)
        }
    }
}
