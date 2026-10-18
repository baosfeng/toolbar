import Foundation

// MARK: - 响应写出

/// 精简 HTTP/1.1 响应编码 — 每连接一请求，统一 `Connection: close`
///
/// 只负责把 `HttpResponse` 序列化成字节：状态行 + 头部 + 空行 + 请求体；
/// 传输层拿到字节后一次性 `send` 并关闭连接。
public enum HttpResponseWriter {

    /// 状态码文案（未列出的状态返回 `Unknown`）
    public static let statusTexts: [Int: String] = [
        200: "OK",
        206: "Partial Content",
        400: "Bad Request",
        403: "Forbidden",
        404: "Not Found",
        409: "Conflict",
        413: "Payload Too Large",
        500: "Internal Server Error",
    ]

    /// 编码响应（Content-Length 由本方法写入，调用方无需自行设置）
    public static func encode(_ response: HttpResponse) -> Data {
        var output = Data()
        let statusText = statusTexts[response.status] ?? "Unknown"
        output.append(Data("HTTP/1.1 \(response.status) \(statusText)\r\n".utf8))

        var headers = response.headers
        headers["Content-Length"] = String(response.body.count)
        headers["Connection"] = "close"
        if headers["Content-Type"] == nil, !response.body.isEmpty {
            headers["Content-Type"] = "application/json; charset=utf-8"
        }
        // 头部顺序固定，便于联调时肉眼比对
        for name in headers.keys.sorted() {
            guard let value = headers[name] else { continue }
            output.append(Data("\(name): \(value)\r\n".utf8))
        }
        output.append(Data("\r\n".utf8))
        output.append(response.body)
        return output
    }

    /// 快速构造业务成功响应（HTTP 200）
    public static func ok<T: Codable & Sendable>(_ data: T) -> HttpResponse {
        HttpResponse.json(ApiResponse<T>.success(data).encoded(), status: 200)
    }

    /// 快速构造业务失败响应
    public static func failure(_ error: TransferError) -> HttpResponse {
        HttpResponse.failure(error)
    }
}
