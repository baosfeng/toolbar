import Foundation
import Network

// MARK: - 精简 HTTP 服务端

/// `NWListener` 上的精简 HTTP/1.1 服务端 — 每连接只处理一个请求
///
/// 职责边界：
/// - 解析请求行 / 头部 / 查询参数（`HttpRequestParser`）
/// - 小请求体（`GET` / `POST`）读取完整 `Data`；`PUT /upload` 交给 `HttpBodyReader` 流式消费
/// - 把 `HttpRequest` 交给路由处理器，写回 `HttpResponse` 后关闭连接
///
/// 不做事：keep-alive、分块传输编码、TLS、业务规则（谁授权 / 存哪里）。
public final class HttpServer: @unchecked Sendable {

    /// 请求处理回调（路由层注入）
    public typealias Handler = @Sendable (HttpRequest, HttpBodyReader?) async -> HttpResponse

    /// 实际监听端口（启动成功后有效）
    public private(set) var port: UInt16?

    private let queue = DispatchQueue(label: "com.networkmonitor.transfer.http")
    private let logger: LoggingService
    private var listener: NWListener?
    private var handler: Handler?

    public init(logger: LoggingService = AppContext.shared.logger) {
        self.logger = logger
    }

    // MARK: - 生命周期

    /// 启动监听：按候选端口顺序尝试，全部失败抛 `listenerUnavailable`
    @discardableResult
    public func start(portCandidates: [UInt16] = TransferProtocol.defaultPorts,
                      handler: @escaping Handler) async throws -> UInt16 {
        self.handler = handler
        var lastError: TransferError = .listenerUnavailable("没有可用端口")
        for candidate in portCandidates {
            do {
                try await bind(port: candidate)
                port = candidate
                logger.info("HTTP 传输服务已监听端口 \(candidate)")
                return candidate
            } catch let error as TransferError {
                lastError = error
                logger.warning("端口 \(candidate) 监听失败：\(error.message)，尝试下一个")
            }
        }
        throw lastError
    }

    /// 停止监听并释放端口
    public func stop() {
        listener?.cancel()
        listener = nil
        port = nil
    }

    // MARK: - 监听绑定

    private func bind(port: UInt16) async throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw TransferError.listenerUnavailable("端口 \(port) 非法")
        }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        let listener: NWListener
        do {
            listener = try NWListener(using: parameters, on: nwPort)
        } catch {
            throw TransferError.listenerUnavailable("端口 \(port)：\(error.localizedDescription)")
        }

        let guardBox = StartupGuard()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guardBox.once { continuation.resume() }
                case .failed(let error):
                    guardBox.once {
                        listener.cancel()
                        continuation.resume(throwing: TransferError.listenerUnavailable(
                            "端口 \(port)：\(error.localizedDescription)"))
                    }
                case .cancelled:
                    guardBox.once {
                        continuation.resume(throwing: TransferError.listenerUnavailable("端口 \(port) 已取消"))
                    }
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.start(queue: queue)
            // 绑定不应超过 2 秒；超时视为失败，避免启动流程永久挂起
            queue.asyncAfter(deadline: .now() + 2) {
                guardBox.once {
                    listener.cancel()
                    continuation.resume(throwing: TransferError.listenerUnavailable("端口 \(port) 绑定超时"))
                }
            }
        }
        self.listener = listener
    }

    // MARK: - 请求处理

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveHead(connection: connection, accumulated: Data())
    }

    /// 累积数据直到出现头部结束符（`\r\n\r\n`）
    private func receiveHead(connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: TransferProtocol.chunkSize) {
            [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var buffer = accumulated
            if let data { buffer.append(data) }

            if let terminator = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let headData = Data(buffer[buffer.startIndex..<terminator.lowerBound])
                let rest = Data(buffer[terminator.upperBound...])
                self.dispatch(connection: connection, headData: headData, preloaded: rest)
                return
            }
            if buffer.count > HttpRequestParser.maxHeadBytes {
                self.respond(connection: connection,
                             response: .failure(.invalidRequest("请求头超过 64 KiB")))
                return
            }
            if error != nil || isComplete {
                self.respond(connection: connection,
                             response: .failure(.invalidRequest("连接在请求头完成前关闭")))
                return
            }
            self.receiveHead(connection: connection, accumulated: buffer)
        }
    }

    /// 头部就绪后分流：上传走流式 reader，其它请求先读完整 body
    private func dispatch(connection: NWConnection, headData: Data, preloaded: Data) {
        let head: HttpRequestHead
        do {
            head = try HttpRequestParser.parseHead(headData)
        } catch let error as TransferError {
            respond(connection: connection, response: .failure(error))
            return
        } catch {
            respond(connection: connection, response: .failure(.invalidRequest("请求头解析失败")))
            return
        }

        let isUpload = head.method == "PUT" && head.path == TransferProtocol.uploadPath
        if isUpload {
            let reader = HttpBodyReader(connection: connection,
                                        remaining: head.contentLength,
                                        preloaded: preloaded)
            invoke(connection: connection, head: head, body: Data(), reader: reader)
            return
        }

        guard head.contentLength <= Int64(TransferProtocol.maxJSONBody) else {
            respond(connection: connection, response: .failure(.invalidRequest("请求体超过 1 MiB")))
            return
        }
        guard head.contentLength > 0 else {
            invoke(connection: connection, head: head, body: Data(), reader: nil)
            return
        }
        collectBody(connection: connection, head: head, accumulated: preloaded,
                    remaining: head.contentLength)
    }

    /// 读取小请求体（`POST /offer` 的 JSON）
    private func collectBody(connection: NWConnection, head: HttpRequestHead,
                             accumulated: Data, remaining: Int64) {
        if Int64(accumulated.count) >= remaining {
            let body = Data(accumulated.prefix(Int(remaining)))
            invoke(connection: connection, head: head, body: body, reader: nil)
            return
        }
        connection.receive(minimumIncompleteLength: 1, maximumLength: TransferProtocol.chunkSize) {
            [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var buffer = accumulated
            if let data { buffer.append(data) }
            if error != nil {
                self.respond(connection: connection, response: .failure(.invalidRequest("读取请求体失败")))
                return
            }
            if Int64(buffer.count) >= remaining {
                let body = Data(buffer.prefix(Int(remaining)))
                self.invoke(connection: connection, head: head, body: body, reader: nil)
                return
            }
            if isComplete {
                self.respond(connection: connection, response: .failure(.invalidRequest("请求体不完整")))
                return
            }
            self.collectBody(connection: connection, head: head, accumulated: buffer,
                             remaining: remaining)
        }
    }

    /// 交给路由处理并写回响应
    private func invoke(connection: NWConnection, head: HttpRequestHead,
                        body: Data, reader: HttpBodyReader?) {
        guard let handler else {
            respond(connection: connection, response: .failure(.listenerUnavailable("路由未装配")))
            return
        }
        let request = HttpRequest(method: head.method,
                                  path: head.path,
                                  query: head.query,
                                  headers: head.headers,
                                  body: body)
        Task { [weak self] in
            let response = await handler(request, reader)
            self?.respond(connection: connection, response: response)
        }
    }

    /// 写出响应并关闭连接（每连接一请求）
    private func respond(connection: NWConnection, response: HttpResponse) {
        let data = HttpResponseWriter.encode(response)
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

// MARK: - 启动回调保护

/// 保证状态回调只消费一次启动 continuation（ready / failed / 超时三者互斥）
private final class StartupGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var consumed = false

    func once(_ body: () -> Void) {
        lock.lock()
        if consumed {
            lock.unlock()
            return
        }
        consumed = true
        lock.unlock()
        body()
    }
}
