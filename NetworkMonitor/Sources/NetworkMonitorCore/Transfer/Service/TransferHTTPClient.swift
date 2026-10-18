import Foundation

// MARK: - 发送端 HTTP 客户端

/// 发送端 HTTP 客户端 — `URLSession` 封装五条路由，上传走文件流（内存恒定）
///
/// 错误约定：对端返回非 0 业务码时抛 `TransferError.remote`，保留远端 code 与 message；
/// 网络层失败统一抛 `ioFailed`，由 Service 决定是否按 1s/2s/4s 退避重试。
public final class TransferHTTPClient: @unchecked Sendable {

    private let logger: LoggingService
    private let configuration: URLSessionConfiguration
    /// 上传进度 delegate —— 独立对象且被 session 强引用，避免 session 失效时回调已析构的 client
    private let progressDelegate = UploadProgressDelegate()
    private lazy var session: URLSession = URLSession(configuration: configuration,
                                                     delegate: progressDelegate,
                                                     delegateQueue: nil)

    /// 请求超时（秒）；大文件上传靠 `timeoutIntervalForResource` 兜底
    public static let requestTimeout: TimeInterval = 60
    /// 单次传输资源超时（秒）
    public static let resourceTimeout: TimeInterval = 3_600

    public init(logger: LoggingService = AppContext.shared.logger) {
        self.logger = logger
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = Self.requestTimeout
        configuration.timeoutIntervalForResource = Self.resourceTimeout
        configuration.waitsForConnectivity = false
        configuration.httpShouldSetCookies = false
        self.configuration = configuration
    }

    deinit {
        // delegate 是独立对象，失效回调不会触碰已析构的 client
        session.invalidateAndCancel()
    }

    /// 设置上传进度回调（progressKey → 已发送字节）
    public func setProgressHandler(_ handler: (@Sendable (String, Int64) -> Void)?) {
        progressDelegate.setHandler(handler)
    }

    // MARK: - 路由

    /// `GET /info`
    public func deviceInfo(ip: String, port: Int) async throws -> DeviceInfo {
        let request = try makeRequest(path: TransferProtocol.infoPath, method: "GET",
                                      ip: ip, port: port, body: nil, headers: [:])
        let (data, status) = try await run(request)
        return try decode(DeviceInfo.self, from: data, status: status)
    }

    /// `POST /offer` — 返回结果与响应头里的 `X-Pair-Key`（配对成功时由接收端下发）
    public func offer(_ offer: OfferRequest, ip: String, port: Int,
                      pairKey: String?) async throws -> (result: OfferResult, pairingKey: String?) {
        let body = try JSONEncoder().encode(offer)
        var headers: [String: String] = ["Content-Type": "application/json"]
        if let pairKey, !pairKey.isEmpty {
            headers[TransferProtocol.pairKeyHeader] = pairKey
        }
        let request = try makeRequest(path: TransferProtocol.offerPath, method: "POST",
                                      ip: ip, port: port, body: body, headers: headers)
        let (data, response) = try await runWithResponse(request)
        let result = try decode(OfferResult.self, from: data, status: response.statusCode)
        let headerKey = response.value(forHTTPHeaderField: TransferProtocol.pairKeyHeader)
        return (result, result.pairingKey ?? headerKey)
    }

    /// `GET /offer/status?session=`
    public func offerStatus(sessionId: String, ip: String, port: Int) async throws -> OfferStatusResult {
        let request = try makeRequest(path: TransferProtocol.offerStatusPath, method: "GET",
                                      ip: ip, port: port, body: nil, headers: [:],
                                      query: [URLQueryItem(name: "session", value: sessionId)])
        let (data, status) = try await run(request)
        return try decode(OfferStatusResult.self, from: data, status: status)
    }

    /// `PUT /upload?session=&file=&offset=` — 从 `offset` 起上传文件
    ///
    /// 续传（offset > 0）时先把剩余字节切到临时文件，上传完成后删除；
    /// 全新传输直接用源文件，避免多一次磁盘拷贝。
    public func upload(fileURL: URL, fileId: String, offset: Int64, sessionId: String,
                       token: String, ip: String, port: Int,
                       progressKey: String? = nil) async throws -> UploadResult {
        let uploadURL = try prepareUploadSource(fileURL: fileURL, offset: offset)
        defer {
            // 续传切片是临时文件，上传结束后立即清理
            if uploadURL != fileURL { try? FileManager.default.removeItem(at: uploadURL) }
        }

        let headers: [String: String] = [
            "Content-Type": "application/octet-stream",
            TransferProtocol.transferTokenHeader: token,
        ]
        let request = try makeRequest(path: TransferProtocol.uploadPath, method: "PUT",
                                      ip: ip, port: port, body: nil, headers: headers,
                                      query: [URLQueryItem(name: "session", value: sessionId),
                                              URLQueryItem(name: "file", value: fileId),
                                              URLQueryItem(name: "offset", value: String(offset))])
        let (data, status) = try await runUpload(request, fromFile: uploadURL,
                                                 progressKey: progressKey ?? fileId)
        return try decode(UploadResult.self, from: data, status: status)
    }

    /// `POST /cancel?session=`
    public func cancel(sessionId: String, ip: String, port: Int, token: String?) async throws {
        var headers: [String: String] = [:]
        if let token { headers[TransferProtocol.transferTokenHeader] = token }
        let request = try makeRequest(path: TransferProtocol.cancelPath, method: "POST",
                                      ip: ip, port: port, body: Data(), headers: headers,
                                      query: [URLQueryItem(name: "session", value: sessionId)])
        let (data, status) = try await run(request)
        _ = try? decode(EmptyPayload.self, from: data, status: status)
    }

    // MARK: - 请求构造

    private func makeRequest(path: String, method: String, ip: String, port: Int,
                             body: Data?, headers: [String: String],
                             query: [URLQueryItem] = []) throws -> URLRequest {
        var components = URLComponents()
        components.scheme = "http"
        components.host = ip
        components.port = port
        components.path = path
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else {
            throw TransferError.invalidRequest("无法构造 URL：http://\(ip):\(port)\(path)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        return request
    }

    /// 续传时切出剩余字节的临时文件
    private func prepareUploadSource(fileURL: URL, offset: Int64) throws -> URL {
        guard offset > 0 else { return fileURL }
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("transfer-upload-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: temporary.path, contents: nil)
        let output = try FileHandle(forWritingTo: temporary)
        defer { try? output.close() }

        let input = try FileHandle(forReadingFrom: fileURL)
        defer { try? input.close() }
        try input.seek(toOffset: UInt64(offset))
        while true {
            let chunk = try input.read(upToCount: TransferProtocol.chunkSize) ?? Data()
            if chunk.isEmpty { break }
            try output.write(contentsOf: chunk)
        }
        return temporary
    }

    // MARK: - 执行

    /// 执行请求，返回响应体与状态码
    private func run(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await perform(request)
        return (data, response.statusCode)
    }

    /// 执行请求并保留响应头（配对 key 从 `X-Pair-Key` 读取）
    private func runWithResponse(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await perform(request)
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>) in
            let task = session.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: TransferError.ioFailed("请求失败：\(error.localizedDescription)"))
                    return
                }
                guard let http = response as? HTTPURLResponse, let data else {
                    continuation.resume(throwing: TransferError.ioFailed("响应非法"))
                    return
                }
                continuation.resume(returning: (data, http))
            }
            task.resume()
        }
    }

    private func runUpload(_ request: URLRequest, fromFile url: URL,
                           progressKey: String) async throws -> (Data, Int) {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, Int), Error>) in
            let task = session.uploadTask(with: request, fromFile: url) { data, response, error in
                if let error {
                    continuation.resume(throwing: TransferError.ioFailed("上传失败：\(error.localizedDescription)"))
                    return
                }
                guard let http = response as? HTTPURLResponse, let data else {
                    continuation.resume(throwing: TransferError.ioFailed("上传响应非法"))
                    return
                }
                continuation.resume(returning: (data, http.statusCode))
            }
            task.taskDescription = progressKey
            task.resume()
        }
    }

    // MARK: - 响应解码

    private func decode<T: Codable & Sendable>(_ type: T.Type, from data: Data, status: Int) throws -> T {
        let decoder = JSONDecoder()
        if let envelope = try? decoder.decode(ApiResponse<T>.self, from: data) {
            if envelope.code == 0, let payload = envelope.data {
                return payload
            }
            throw TransferError.remote(code: envelope.code, message: envelope.message)
        }
        if let failure = try? decoder.decode(ApiResponse<EmptyPayload>.self, from: data) {
            throw TransferError.remote(code: failure.code, message: failure.message)
        }
        throw TransferError.ioFailed("响应结构非法（HTTP \(status)）")
    }

}

// MARK: - 上传进度 delegate

/// 独立的上传进度 delegate —— 与 client 解耦，避免 session 失效时回调已析构对象
private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (String, Int64) -> Void)?

    func setHandler(_ handler: (@Sendable (String, Int64) -> Void)?) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64,
                    totalBytesExpectedToSend: Int64) {
        guard let key = task.taskDescription else { return }
        lock.lock()
        let handler = self.handler
        lock.unlock()
        handler?(key, totalBytesSent)
    }
}
