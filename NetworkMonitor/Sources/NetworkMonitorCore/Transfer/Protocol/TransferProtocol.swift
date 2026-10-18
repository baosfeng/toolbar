import Foundation

// MARK: - 协议常量

/// 传输协议常量 — 端口、路由、状态取值的唯一出处（与设计文档 §3 对齐）
public enum TransferProtocol {

    /// 路由统一前缀
    public static let routePrefix = "/api/v1"

    /// 设备信息
    public static let infoPath = "/api/v1/info"
    /// 提交文件清单
    public static let offerPath = "/api/v1/offer"
    /// 查询会话确认状态
    public static let offerStatusPath = "/api/v1/offer/status"
    /// 单文件二进制上传
    public static let uploadPath = "/api/v1/upload"
    /// 中止会话
    public static let cancelPath = "/api/v1/cancel"

    /// 默认 HTTP 端口；被占用时顺延到 53328
    public static let defaultPorts: [UInt16] = [53319, 53320, 53321, 53322, 53323,
                                                53324, 53325, 53326, 53327, 53328]

    /// 配对免确认请求头
    public static let pairKeyHeader = "X-Pair-Key"
    /// 会话上传令牌请求头
    public static let transferTokenHeader = "X-Transfer-Token"

    /// 确认超时时长（秒）
    public static let confirmTimeout: TimeInterval = 30
    /// 无字节进展超时（秒）
    public static let idleTimeout: TimeInterval = 60
    /// 单次读取 / 写入缓冲区（64 KiB，内存与文件大小无关）
    public static let chunkSize = 64 * 1024
    /// 小请求体上限（`POST /offer` JSON）
    public static let maxJSONBody = 1 * 1024 * 1024
}

// MARK: - 会话确认状态

/// `offer` 返回与 `offer/status` 查询的会话状态字符串
public enum OfferState: String, Codable, Sendable, CaseIterable {
    case pending
    case approved
    case denied
    case expired
}

// MARK: - 统一响应信封

/// 响应信封 `{code, message, data}` — 沿用 Android 端既有约定
///
/// 自定义编解码：`data` 为 nil 时显式输出 `null`（合成 Codable 会省略该键，
/// 破坏两端约定的三字段结构）。
public struct ApiResponse<T: Codable & Sendable>: Codable, Sendable {
    public var code: Int
    public var message: String
    public var data: T?

    private enum CodingKeys: String, CodingKey {
        case code, message, data
    }

    public init(code: Int = 0, message: String = "ok", data: T? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(Int.self, forKey: .code)
        message = try container.decodeIfPresent(String.self, forKey: .message) ?? "ok"
        data = try container.decodeIfPresent(T.self, forKey: .data)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(code, forKey: .code)
        try container.encode(message, forKey: .message)
        if let data {
            try container.encode(data, forKey: .data)
        } else {
            try container.encodeNil(forKey: .data)
        }
    }

    /// 成功响应
    public static func success(_ data: T, message: String = "ok") -> ApiResponse<T> {
        ApiResponse(code: 0, message: message, data: data)
    }

    /// 失败响应（data 为 null）
    public static func failure(_ error: TransferError) -> ApiResponse<T> {
        ApiResponse(code: error.code, message: error.message, data: nil)
    }

    /// 编码为 JSON（字段顺序固定，便于联调比对）
    public func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(self)) ?? Data(#"{"code":500,"message":"编码失败","data":null}"#.utf8)
    }
}

/// 空 data 占位（`/cancel` 成功时 data 为 `{}`）
public struct EmptyPayload: Codable, Sendable {
    public init() {}
}

// MARK: - /info

/// 设备信息与能力 — 字段与发现消息保持一致，避免两端漂移
public struct DeviceInfo: Codable, Sendable, Equatable {
    public var deviceId: String
    public var alias: String
    public var deviceType: String
    public var appVersion: String
    public var proto: String
    public var caps: [String]
    public var port: Int

    public init(deviceId: String, alias: String, deviceType: String = "mac",
                appVersion: String, proto: String = "http", caps: [String] = ["send", "recv"],
                port: Int) {
        self.deviceId = deviceId
        self.alias = alias
        self.deviceType = deviceType
        self.appVersion = appVersion
        self.proto = proto
        self.caps = caps
        self.port = port
    }

    /// 由本机身份构造
    public init(identity: LocalIdentity) {
        self.init(deviceId: identity.deviceId,
                  alias: identity.alias,
                  appVersion: identity.appVersion,
                  port: identity.port)
    }
}

// MARK: - /offer

/// 清单中的单个文件
public struct OfferFile: Codable, Sendable, Equatable {
    public var fileId: String
    public var name: String
    public var size: Int64
    public var sha256: String
    public var mime: String

    public init(fileId: String, name: String, size: Int64, sha256: String,
                mime: String = "application/octet-stream") {
        self.fileId = fileId
        self.name = name
        self.size = size
        self.sha256 = sha256
        self.mime = mime
    }
}

/// `POST /offer` 请求体
public struct OfferRequest: Codable, Sendable, Equatable {
    public var senderDeviceId: String
    public var senderAlias: String
    public var files: [OfferFile]
    /// 重提 PIN 时携带上次返回的会话 id（可选；缺失时接收端按清单复用）
    public var sessionId: String?
    /// 未配对时用户输入的 4 位 PIN（可选，重新提交时携带）
    public var pin: String?

    public init(senderDeviceId: String, senderAlias: String, files: [OfferFile],
                sessionId: String? = nil, pin: String? = nil) {
        self.senderDeviceId = senderDeviceId
        self.senderAlias = senderAlias
        self.files = files
        self.sessionId = sessionId
        self.pin = pin
    }

    /// 解码并做字段校验（空清单 / 非法大小视为请求体非法）
    public static func decode(_ data: Data) throws -> OfferRequest {
        let request: OfferRequest
        do {
            request = try JSONDecoder().decode(OfferRequest.self, from: data)
        } catch {
            throw TransferError.malformedBody("清单 JSON 无法解析")
        }
        guard !request.senderDeviceId.isEmpty else {
            throw TransferError.malformedBody("缺少 senderDeviceId")
        }
        guard !request.files.isEmpty else {
            throw TransferError.malformedBody("files 不能为空")
        }
        for file in request.files {
            guard !file.fileId.isEmpty, !file.name.isEmpty, file.size >= 0 else {
                throw TransferError.malformedBody("文件条目字段非法：\(file.fileId)")
            }
        }
        return request
    }
}

/// 已接受文件及其续传起点
public struct AcceptedFile: Codable, Sendable, Equatable {
    public var fileId: String
    public var offset: Int64

    public init(fileId: String, offset: Int64) {
        self.fileId = fileId
        self.offset = offset
    }
}

/// `POST /offer` / `GET /offer/status` 的 data
public struct OfferResult: Codable, Sendable, Equatable {
    public var sessionId: String
    public var token: String
    public var state: OfferState
    public var accepted: [AcceptedFile]
    /// 本次完成**新配对**时由接收端生成（32 字节小写 hex）；已配对重传不出现
    public var pairingKey: String?

    public init(sessionId: String, token: String, state: OfferState,
                accepted: [AcceptedFile] = [], pairingKey: String? = nil) {
        self.sessionId = sessionId
        self.token = token
        self.state = state
        self.accepted = accepted
        self.pairingKey = pairingKey
    }
}

/// `POST /offer` 处理结果 — 除响应体外还需下发 `X-Pair-Key` 响应头（配对成功时）
public struct OfferHandlingResult: Sendable, Equatable {
    /// 响应体 data
    public var result: OfferResult
    /// 本次新签发的配对 key（未发生配对为 nil）
    public var issuedPairingKey: String?

    public init(result: OfferResult, issuedPairingKey: String? = nil) {
        self.result = result
        self.issuedPairingKey = issuedPairingKey
    }
}

/// `GET /offer/status` 的 data
public struct OfferStatusResult: Codable, Sendable, Equatable {
    public var state: OfferState

    public init(state: OfferState) {
        self.state = state
    }
}

// MARK: - /upload

/// `PUT /upload` 成功后的 data
public struct UploadResult: Codable, Sendable, Equatable {
    public var fileId: String
    public var received: Int64
    public var sha256: String

    public init(fileId: String, received: Int64, sha256: String) {
        self.fileId = fileId
        self.received = received
        self.sha256 = sha256
    }
}

// MARK: - HTTP 抽象

/// HTTP 字节区间（`Range: bytes=start-end`）
public struct HttpByteRange: Equatable, Sendable {
    public var start: Int64
    public var end: Int64?

    public init(start: Int64, end: Int64? = nil) {
        self.start = start
        self.end = end
    }

    /// 解析 `bytes=0-1023` / `bytes=512-`；格式非法返回 nil
    public static func parse(_ value: String?) -> HttpByteRange? {
        guard let value, value.hasPrefix("bytes=") else { return nil }
        let spec = value.dropFirst("bytes=".count)
        let parts = spec.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, let start = Int64(parts[0]), start >= 0 else { return nil }
        if parts[1].isEmpty { return HttpByteRange(start: start, end: nil) }
        guard let end = Int64(parts[1]), end >= start else { return nil }
        return HttpByteRange(start: start, end: end)
    }
}

/// 已解析的 HTTP 请求（路由层只依赖此抽象）
public struct HttpRequest: Sendable {
    public var method: String
    /// 不含查询串的路径
    public var path: String
    /// 查询参数（已做百分号解码）
    public var query: [String: String]
    /// 头部（key 已小写化）
    public var headers: [String: String]
    /// 小请求体（流式上传时为空）
    public var body: Data

    public init(method: String, path: String, query: [String: String] = [:],
                headers: [String: String] = [:], body: Data = Data()) {
        self.method = method
        self.path = path
        self.query = query
        self.headers = headers
        self.body = body
    }

    /// 取头部（大小写不敏感）
    public func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }

    /// 取查询参数
    public func queryValue(_ name: String) -> String? {
        query[name]
    }

    /// `Range` 头
    public var range: HttpByteRange? {
        HttpByteRange.parse(header("range"))
    }
}

/// 待写出的 HTTP 响应
public struct HttpResponse: Sendable {
    public var status: Int
    public var headers: [String: String]
    public var body: Data

    public init(status: Int = 200, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    /// JSON 响应
    public static func json(_ body: Data, status: Int = 200) -> HttpResponse {
        HttpResponse(status: status,
                     headers: ["Content-Type": "application/json; charset=utf-8"],
                     body: body)
    }

    /// 业务失败响应（HTTP 状态按错误类型映射）
    public static func failure(_ error: TransferError) -> HttpResponse {
        let payload = ApiResponse<EmptyPayload>.failure(error)
        return .json(payload.encoded(), status: error.httpStatus)
    }
}

// MARK: - 错误码映射

public extension TransferError {
    /// 对应 HTTP 状态码（业务码仍在响应体 `code` 中）
    var httpStatus: Int {
        switch self {
        case .routeNotFound: return 404
        case .invalidRequest, .malformedBody, .tokenMismatch, .sessionNotFound,
             .offsetMismatch, .diskFull, .checksumMismatch, .denied, .confirmTimeout,
             .illegalTransition, .remote:
            return 400
        case .ioFailed, .listenerUnavailable, .discoverySocket, .discoveryBind:
            return 500
        }
    }
}
