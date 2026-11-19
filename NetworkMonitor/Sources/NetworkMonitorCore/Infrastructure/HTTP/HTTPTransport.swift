import Foundation

// MARK: - 失败分类

/// 一次出网的失败 —— 传输层只区分「发不出去」「不是 HTTP」「发出去但状态不对」
///
/// provider 在自己的 errorMapper 里把这三类翻成领域错误（BillingError / UpdateCheckError ...），
/// 从而做到「状态码 → 错误只留一份、话术各留各的」。
public enum HTTPFailure: Sendable {
    /// 连接失败 / 超时 / 被取消
    case transport(HTTPTransportFailure)
    /// 响应不是 HTTP 响应（极罕见，等价于改造前的 invalidResponse("非 HTTP 响应")）
    case notHTTP
    /// 非 2xx（含状态码、白名单头与错误体文案）
    case response(HTTPResponse)
}

/// 传输失败的结构化描述 —— 只保留「能区分超时 / 取消」的信息（领域错误依赖这个区分）
public struct HTTPTransportFailure: Equatable, Sendable {
    /// 原始错误描述（与改造前 error.localizedDescription 同源）
    public let message: String
    /// 是否超时（URLError.timedOut）
    public let isTimeout: Bool
    /// 是否被取消（URLError.cancelled）
    public let isCancelled: Bool

    public init(message: String, isTimeout: Bool = false, isCancelled: Bool = false) {
        self.message = message
        self.isTimeout = isTimeout
        self.isCancelled = isCancelled
    }

    /// 从捕获到的错误装箱
    public static func make(_ error: any Error) -> HTTPTransportFailure {
        let urlError = error as? URLError
        return HTTPTransportFailure(message: error.localizedDescription,
                                    isTimeout: urlError?.code == .timedOut,
                                    isCancelled: urlError?.code == .cancelled)
    }
}

/// 失败 → 领域错误
public typealias HTTPErrorMapper = @Sendable (HTTPFailure) -> any Error

// MARK: - 传输协议

/// 唯一 HTTP 出网协议 —— 除局域网文件流（TransferHTTPClient）外，全仓只此一个实现
///
/// 契约：
/// - 只做「发出去 + 装箱 + 脱敏日志」，状态码语义与用户话术交给 endpoint；
/// - 2xx 时调用 endpoint.decoder，其抛出的错误原样向外抛（解码错误不二次包装）；
/// - 非 2xx / 传输失败一律经 endpoint.errorMapper（缺省用 HTTPTransportDefaults.error）。
public protocol HTTPTransport: Sendable {
    func send<Response: Sendable>(_ endpoint: Endpoint<Response>) async throws -> Response
}

// MARK: - URLSession 实现

/// 基于 URLSession 的传输实现 —— 全仓唯一（TransferHTTPClient 的文件流上传除外）
public final class URLSessionHTTPTransport: HTTPTransport {

    private let session: URLSession
    private let logger: LoggingService

    /// - Parameter logger: 显式注入（Core 里不默认绑 AppContext.shared）
    public init(session: URLSession = .shared, logger: LoggingService) {
        self.session = session
        self.logger = logger
    }

    public func send<Response: Sendable>(_ endpoint: Endpoint<Response>) async throws -> Response {
        let request = makeRequest(endpoint)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            // 失败日志统一在这里出：URL 只留 host + path，头不打印（脱敏不靠 provider 自觉）
            logger.warning("\(endpoint.label) 请求网络失败：\(HTTPLogRedaction.url(endpoint.url)) — \(error.localizedDescription)")
            throw map(endpoint, .transport(HTTPTransportFailure.make(error)))
        }
        guard let http = response as? HTTPURLResponse else {
            logger.warning("\(endpoint.label) 响应不是 HTTP：\(HTTPLogRedaction.url(endpoint.url))")
            throw map(endpoint, .notHTTP)
        }
        let boxed = HTTPResponse(data: data,
                                 statusCode: http.statusCode,
                                 headers: Self.lowercasedHeaders(http),
                                 message: (200..<300).contains(http.statusCode)
                                     ? nil : HTTPErrorBody.message(from: data))
        guard boxed.isSuccess else {
            // 非 2xx 也留一条 warning（等级与改造前各 provider 一致），URL 与头均脱敏
            logger.warning("\(endpoint.label) 请求失败：\(HTTPLogRedaction.url(endpoint.url)) — HTTP \(boxed.statusCode) \(HTTPLogRedaction.headers(boxed.headers))")
            throw map(endpoint, .response(boxed))
        }
        return try endpoint.decoder(data)
    }

    // MARK: 请求构造

    /// 组装请求 —— 头 / 体 / 超时 / 缓存策略全部来自 Endpoint，默认 UA 与 Accept 只在缺省时补
    ///
    /// public 供 TestRunner 直接断言「声明 → 真实请求」的映射（不联网也能测超时与头）。
    public func makeRequest<Response: Sendable>(_ endpoint: Endpoint<Response>) -> URLRequest {
        var request = URLRequest(url: endpoint.url)
        request.httpMethod = endpoint.method.rawValue
        request.httpBody = endpoint.body
        request.timeoutInterval = endpoint.timeout
        request.cachePolicy = endpoint.cachePolicy
        for (name, value) in endpoint.headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        if let userAgent = endpoint.userAgent {
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }
        if request.value(forHTTPHeaderField: "Accept") == nil {
            request.setValue(HTTPTransportDefaults.accept, forHTTPHeaderField: "Accept")
        }
        return request
    }

    // MARK: 失败映射

    private func map<Response: Sendable>(_ endpoint: Endpoint<Response>, _ failure: HTTPFailure) -> any Error {
        let mapper = endpoint.errorMapper ?? HTTPTransportDefaults.error
        return mapper(failure)
    }

    /// 响应头 → 小写键字典（Retry-After / X-RateLimit-Remaining 等判定靠它）
    public static func lowercasedHeaders(_ response: HTTPURLResponse) -> [String: String] {
        var result: [String: String] = [:]
        for (name, value) in response.allHeaderFields {
            guard let key = name as? String, let text = value as? String else { continue }
            result[key.lowercased()] = text
        }
        return result
    }
}
