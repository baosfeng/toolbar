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

    /// 带字节进度的下载 —— 返回值与 `send` 完全一致，只是中途多报进度
    ///
    /// 默认实现直接退回 `send`（旧替身无需实现即可编译，进度为空也不影响正确性）；
    /// 真实实现覆写成流式，见 `URLSessionHTTPTransport.download`。
    ///
    /// - Parameter progress: 已接收字节与总量（总量 nil = 服务端没给 Content-Length）
    func download(_ endpoint: Endpoint<Data>,
                  progress: @Sendable (_ received: Int64, _ total: Int64?) -> Void) async throws -> Data
}

public extension HTTPTransport {
    /// 默认退回原子实现 —— 「不实现也能编译」是这条协议的兼容契约
    func download(_ endpoint: Endpoint<Data>,
                  progress: @Sendable (_ received: Int64, _ total: Int64?) -> Void) async throws -> Data {
        try await send(endpoint)
    }
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

    // MARK: 流式下载

    /// 流式下载 —— 唯一需要「中途可观测」的出网点（更新安装包）
    ///
    /// 为什么不是 delegate：`URLSession.bytes(for:)` 在 macOS 12 起可用（本项目最低 14），
    /// 不需要 NSObject 子类、不破坏本类型的值语义，取消语义由 `AsyncBytes.task` 承担。
    ///
    /// 坑（实测必须这么写）：**非 2xx 的流式响应会污染字节计数**。状态码在
    /// `bytes(for:)` 返回时就已经拿到，所以先判状态码：非 2xx 时只读前 64KB 用来取
    /// 错误体文案，然后立刻停止读取并走 `errorMapper` —— 绝不能把 403 页面当成安装包累加。
    public func download(_ endpoint: Endpoint<Data>,
                         progress: @Sendable (_ received: Int64, _ total: Int64?) -> Void) async throws -> Data {
        let request = makeRequest(endpoint)
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch {
            logger.warning("\(endpoint.label) 请求网络失败：\(HTTPLogRedaction.url(endpoint.url)) — \(error.localizedDescription)")
            throw map(endpoint, .transport(HTTPTransportFailure.make(error)))
        }
        guard let http = response as? HTTPURLResponse else {
            logger.warning("\(endpoint.label) 响应不是 HTTP：\(HTTPLogRedaction.url(endpoint.url))")
            throw map(endpoint, .notHTTP)
        }
        // 分母优先取服务端声明，其次留给调用方（清单里的 byteCount）兜底
        let expected: Int64? = http.expectedContentLength > 0 ? http.expectedContentLength : nil

        guard (200..<300).contains(http.statusCode) else {
            let body = await Self.drainPrefix(bytes, limit: 64 * 1024)
            let boxed = HTTPResponse(data: body,
                                     statusCode: http.statusCode,
                                     headers: Self.lowercasedHeaders(http),
                                     message: HTTPErrorBody.message(from: body))
            logger.warning("\(endpoint.label) 请求失败：\(HTTPLogRedaction.url(endpoint.url)) — HTTP \(boxed.statusCode) \(HTTPLogRedaction.headers(boxed.headers))")
            throw map(endpoint, .response(boxed))
        }

        // 分块累积：逐字节 append 到 Data 对 12MB 的包太慢，先攒进 [UInt8] 再整块追加
        var buffer: [UInt8] = []
        buffer.reserveCapacity(64 * 1024)
        var result = Data()
        if let expected { result.reserveCapacity(Int(min(expected, 64 * 1024 * 1024))) }
        var received: Int64 = 0
        progress(0, expected)
        do {
            for try await byte in bytes {
                buffer.append(byte)
                guard buffer.count >= 64 * 1024 else { continue }
                result.append(contentsOf: buffer)
                received += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                progress(received, expected)
            }
        } catch {
            logger.warning("\(endpoint.label) 下载中断：\(HTTPLogRedaction.url(endpoint.url)) — \(error.localizedDescription)")
            throw map(endpoint, .transport(HTTPTransportFailure.make(error)))
        }
        if !buffer.isEmpty {
            result.append(contentsOf: buffer)
            received += Int64(buffer.count)
        }
        progress(received, expected ?? received)
        return result
    }

    /// 只读前 `limit` 字节（非 2xx 时取错误体；读完即释放流，不把整页错误页收进内存）
    private static func drainPrefix(_ bytes: URLSession.AsyncBytes, limit: Int) async -> Data {
        var buffer: [UInt8] = []
        buffer.reserveCapacity(min(limit, 8 * 1024))
        do {
            for try await byte in bytes {
                buffer.append(byte)
                if buffer.count >= limit { break }
            }
        } catch {
            // 读错误体失败不影响判定：状态码已经拿到，错误体只是可选的补充文案
        }
        return Data(buffer)
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

// MARK: - 共享默认实例

public extension URLSessionHTTPTransport {
    /// 全仓共享的默认实例 —— 只在调用方未显式注入时求值
    ///
    /// 应用内的 provider 与更新链路都由组合根创建实例后按协议注入，本默认值留给
    /// 测试与独立调用点，从而让 URLSession 的构造点不再散落在各 provider 内部。
    static let shared = URLSessionHTTPTransport(session: .shared, logger: AppContext.shared.logger)
}
