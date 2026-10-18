import Foundation

// MARK: - 路由处理协议

/// 路由处理协议 — Protocol 层只定义「要做什么」，具体业务由 Service 层实现
///
/// 与设计文档 §2 的分层一致：Protocol 不写磁盘、不决定业务规则；
/// 这里的方法只负责把已解析的请求翻译成领域调用，并返回统一结果。
public protocol TransferRouteHandling: AnyObject, Sendable {
    /// `GET /info`：设备信息与能力
    func deviceInfo() async -> DeviceInfo

    /// `POST /offer`：提交清单，返回会话与状态（`pending` 不阻塞，由客户端轮询状态）
    func handleOffer(_ request: OfferRequest, pairKey: String?) async -> Result<OfferHandlingResult, TransferError>

    /// `GET /offer/status`：查询会话确认状态
    func offerStatus(sessionId: String) async -> Result<OfferStatusResult, TransferError>

    /// `PUT /upload`：从 `offset` 起接收流式上传并落盘
    func receiveUpload(sessionId: String, fileId: String, offset: Int64, token: String?,
                       body: HttpBodyReader) async -> Result<UploadResult, TransferError>

    /// `POST /cancel`：中止会话并清理 `.part`
    func cancel(sessionId: String, token: String?) async -> Result<EmptyPayload, TransferError>
}

// MARK: - 路由分发

/// 路由分发 — 把 `HttpRequest` 映射到 `TransferRouteHandling`
///
/// 统一响应 `{code, message, data}`；未知路径返回 HTTP 404，业务失败按错误码映射状态码。
public final class TransferRouter: @unchecked Sendable {

    private let handler: any TransferRouteHandling

    public init(handler: any TransferRouteHandling) {
        self.handler = handler
    }

    /// 分发并返回响应（每连接一请求，调用方写完即关闭连接）
    public func route(_ request: HttpRequest, body: HttpBodyReader?) async -> HttpResponse {
        do {
            let response = try await dispatch(request, body: body)
            return response
        } catch let error as TransferError {
            return .failure(error)
        } catch {
            return .failure(.ioFailed("路由处理异常：\(error.localizedDescription)"))
        }
    }

    // MARK: - 内部

    private func dispatch(_ request: HttpRequest, body: HttpBodyReader?) async throws -> HttpResponse {
        switch (request.method, request.path) {
        case ("GET", TransferProtocol.infoPath):
            let info = await handler.deviceInfo()
            return HttpResponseWriter.ok(info)

        case ("POST", TransferProtocol.offerPath):
            let offer = try OfferRequest.decode(request.body)
            let result = await handler.handleOffer(offer, pairKey: request.header(TransferProtocol.pairKeyHeader))
            switch result {
            case .success(let outcome):
                var response = HttpResponse.json(
                    ApiResponse<OfferResult>.success(outcome.result).encoded())
                if let issuedKey = outcome.issuedPairingKey {
                    response.headers[TransferProtocol.pairKeyHeader] = issuedKey
                }
                return response
            case .failure(let error):
                return .failure(error)
            }

        case ("GET", TransferProtocol.offerStatusPath):
            guard let sessionId = request.queryValue("session"), !sessionId.isEmpty else {
                throw TransferError.invalidRequest("缺少 session 参数")
            }
            let result = await handler.offerStatus(sessionId: sessionId)
            return respond(result)

        case ("PUT", TransferProtocol.uploadPath):
            guard let sessionId = request.queryValue("session"), !sessionId.isEmpty else {
                throw TransferError.invalidRequest("缺少 session 参数")
            }
            guard let fileId = request.queryValue("file"), !fileId.isEmpty else {
                throw TransferError.invalidRequest("缺少 file 参数")
            }
            guard let offsetText = request.queryValue("offset"), let offset = Int64(offsetText), offset >= 0 else {
                throw TransferError.invalidRequest("offset 参数缺失或非法")
            }
            guard let body else {
                throw TransferError.invalidRequest("缺少请求体读取器")
            }
            let result = await handler.receiveUpload(sessionId: sessionId, fileId: fileId,
                                                     offset: offset,
                                                     token: request.header(TransferProtocol.transferTokenHeader),
                                                     body: body)
            return respond(result)

        case ("POST", TransferProtocol.cancelPath):
            guard let sessionId = request.queryValue("session"), !sessionId.isEmpty else {
                throw TransferError.invalidRequest("缺少 session 参数")
            }
            let result = await handler.cancel(sessionId: sessionId,
                                              token: request.header(TransferProtocol.transferTokenHeader))
            return respond(result)

        default:
            // 路径存在但方法不对，也按「路由不存在」返回，避免暴露内部结构
            throw TransferError.routeNotFound("\(request.method) \(request.path)")
        }
    }

    /// `Result` → 统一响应信封
    private func respond<T: Codable & Sendable>(_ result: Result<T, TransferError>) -> HttpResponse {
        switch result {
        case .success(let data):
            return HttpResponse.json(ApiResponse<T>.success(data).encoded())
        case .failure(let error):
            return .failure(error)
        }
    }
}
