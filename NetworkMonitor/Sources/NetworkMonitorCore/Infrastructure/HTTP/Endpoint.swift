import Foundation

// MARK: - 端点声明

/// HTTP 方法 —— 只列举本仓真用到的三种，避免把写错的字符串带进请求
public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
}

/// 一个出网点的全部声明 —— 地址 / 头 / 体 / 超时 / 缓存策略 / 解码 / 错误映射
///
/// 设计口径：
/// - 值类型 + 闭包，构造后不可变：调用方只描述「打哪个地址、怎么解」，不碰 URLSession；
/// - 超时逐 endpoint 可覆写（默认 15s，见 HTTPTransportDefaults.timeout），
///   限流语义特殊的端点（如 GitHub 8s）在自己的 Endpoint 里写死；
/// - 错误映射是本端点的可选覆写钩子：403 / 401 的用户话术各家不同，
///   未提供时走 HTTPTransportDefaults.error 的统一口径。
///
/// 未定义行为处置：
/// - decoder 抛什么就向外抛什么（解码错误走这条，不做二次包装）；
/// - 传输失败 / 非 2xx 一律转换成 errorMapper 的产物，绝不把裸 URLError 漏给上层。
public struct Endpoint<Response: Sendable>: Sendable {
    /// 方法
    public let method: HTTPMethod
    /// 完整请求地址（含 query）
    public let url: URL
    /// 业务头（凭据 / Accept / 来源头）；传输层会补默认 UA 与 Accept（缺省时）
    public let headers: [String: String]
    /// 请求体（GET 为 nil）
    public let body: Data?
    /// User-Agent（nil = 不发 UA，保持「改造前就没发 UA」的端点零变化）
    public let userAgent: String?
    /// 超时（秒）—— 逐 endpoint 覆写
    public let timeout: TimeInterval
    /// 缓存策略（GitHub 更新检查要 reloadIgnoringLocalCacheData）
    public let cachePolicy: URLRequest.CachePolicy
    /// 响应体 → 领域值
    public let decoder: @Sendable (Data) throws -> Response
    /// 失败（传输失败 / 非 HTTP / 非 2xx）→ 领域错误；nil 时用统一口径
    public let errorMapper: HTTPErrorMapper?
    /// 日志用标识（provider 展示名 /「更新检查」）；失败日志靠它定位
    public let label: String

    public init(method: HTTPMethod = .get,
                url: URL,
                headers: [String: String] = [:],
                body: Data? = nil,
                userAgent: String? = nil,
                timeout: TimeInterval = HTTPTransportDefaults.timeout,
                cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy,
                label: String,
                decoder: @escaping @Sendable (Data) throws -> Response,
                errorMapper: HTTPErrorMapper? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.userAgent = userAgent
        self.timeout = timeout
        self.cachePolicy = cachePolicy
        self.label = label
        self.decoder = decoder
        self.errorMapper = errorMapper
    }
}

/// 端点共用默认值 —— 超时 / UA / Accept / 统一错误口径的唯一真源
public enum HTTPTransportDefaults {
    /// 默认超时（秒）：15 秒足够，且不会让一次刷新长时间占住刷新节拍
    public static let timeout: TimeInterval = 15
    /// 额度 provider 的 User-Agent（部分站点对空 UA 直接 403；改这一处即全体额度请求）
    public static let userAgent = "NetworkMonitor/1.0 (macOS)"
    /// 默认 Accept
    public static let accept = "application/json"

    /// 统一失败口径（provider 未覆写时使用）：
    /// 传输失败 → transport；非 HTTP → notHTTP；非 2xx → 按 400/401/403/429/5xx 分级
    public static func error(_ failure: HTTPFailure) -> any Error {
        switch failure {
        case .transport(let failure):
            return HTTPTransportError.transport(failure.message)
        case .notHTTP:
            return HTTPTransportError.notHTTP
        case .response(let response):
            return HTTPTransportError.status(HTTPStatusCode.map(response.statusCode,
                                                               retryAfter: response.retryAfter,
                                                               message: response.message))
        }
    }
}

// MARK: - 传输层错误

/// 传输层自身的失败分类 —— 与业务错误（BillingError / UpdateCheckError ...）解耦：
/// 调用方在自己的 errorMapper 里把它翻成领域错误，或在解码前按类型分流。
public enum HTTPTransportError: Error, Equatable, Sendable {
    /// 连接失败 / 超时 / 被取消（原始错误描述原样保留）
    case transport(String)
    /// 非 2xx（已按统一口径映射成领域无关的分级）
    case status(HTTPStatusCode)
    /// 响应不是 HTTP 响应
    case notHTTP
}
