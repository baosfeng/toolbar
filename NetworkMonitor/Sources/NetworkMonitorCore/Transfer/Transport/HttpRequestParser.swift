import Foundation

// MARK: - 请求头

/// 已解析的请求头（请求行 + 头部 + Content-Length）
public struct HttpRequestHead: Equatable, Sendable {
    public var method: String
    /// 不含查询串的路径
    public var path: String
    public var query: [String: String]
    /// 头部 key 统一小写
    public var headers: [String: String]
    public var contentLength: Int64
    public var range: HttpByteRange?

    public init(method: String, path: String, query: [String: String] = [:],
                headers: [String: String] = [:], contentLength: Int64 = 0,
                range: HttpByteRange? = nil) {
        self.method = method
        self.path = path
        self.query = query
        self.headers = headers
        self.contentLength = contentLength
        self.range = range
    }

    /// 取头部（大小写不敏感）
    public func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }
}

// MARK: - 请求解析

/// 精简 HTTP/1.1 请求解析 — 只覆盖本协议用到的 GET / POST / PUT
///
/// 解析规则：
/// - 请求行必须为 `METHOD SP TARGET SP HTTP/1.x`，方法只接受 `GET` / `POST` / `PUT`
/// - 目标拆成路径 + 查询参数，参数值做百分号解码
/// - 头部大小写不敏感，同名头部按逗号合并
/// - `Content-Length` 缺失视为 0，非法直接判请求非法（不猜测长度）
public enum HttpRequestParser {

    /// 头部最大长度（超出判非法，避免恶意连接吃内存）
    public static let maxHeadBytes = 64 * 1024
    /// 允许的方法
    public static let allowedMethods: Set<String> = ["GET", "POST", "PUT"]

    /// 解析完整头部块（必须包含结尾空行）
    public static func parseHead(_ data: Data) throws -> HttpRequestHead {
        guard let text = String(data: data, encoding: .utf8) else {
            throw TransferError.invalidRequest("请求头不是合法 UTF-8")
        }
        let lines = text.components(separatedBy: "\r\n")
        guard let requestLine = lines.first, !requestLine.isEmpty else {
            throw TransferError.invalidRequest("缺少请求行")
        }

        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 3 else {
            throw TransferError.invalidRequest("请求行格式非法：\(requestLine)")
        }
        let method = String(parts[0]).uppercased()
        guard allowedMethods.contains(method) else {
            throw TransferError.invalidRequest("不支持的方法：\(method)")
        }
        guard parts[2].hasPrefix("HTTP/1.") else {
            throw TransferError.invalidRequest("不支持的 HTTP 版本：\(parts[2])")
        }
        guard let target = parseTarget(String(parts[1])) else {
            throw TransferError.invalidRequest("请求目标非法：\(parts[1])")
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard !line.isEmpty else { break }
            guard let separator = line.firstIndex(of: ":") else {
                throw TransferError.invalidRequest("头部行缺少冒号：\(line)")
            }
            let name = String(line[line.startIndex..<separator]).lowercased()
                .trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else {
                throw TransferError.invalidRequest("头部名为空")
            }
            if let existing = headers[name], !existing.isEmpty {
                headers[name] = existing + "," + value
            } else {
                headers[name] = value
            }
        }

        let contentLength: Int64
        if let rawLength = headers["content-length"] {
            guard let parsed = Int64(rawLength), parsed >= 0 else {
                throw TransferError.invalidRequest("Content-Length 非法：\(rawLength)")
            }
            contentLength = parsed
        } else {
            contentLength = 0
        }

        return HttpRequestHead(method: method,
                               path: target.path,
                               query: target.query,
                               headers: headers,
                               contentLength: contentLength,
                               range: HttpByteRange.parse(headers["range"]))
    }

    /// 拆分 `路径?查询串` 并做百分号解码
    public static func parseTarget(_ target: String) -> (path: String, query: [String: String])? {
        guard target.hasPrefix("/") else { return nil }
        guard let markIndex = target.firstIndex(of: "?") else {
            return (target, [:])
        }
        let path = String(target[target.startIndex..<markIndex])
        let queryText = String(target[target.index(after: markIndex)...])
        var query: [String: String] = [:]
        for pair in queryText.split(separator: "&", omittingEmptySubsequences: true) {
            let pieces = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let rawName = pieces.first, !rawName.isEmpty else { continue }
            let rawValue = pieces.count > 1 ? String(pieces[1]) : ""
            let name = decode(rawName)
            let value = decode(Substring(rawValue))
            if let name { query[name] = value ?? "" }
        }
        return (path, query)
    }

    /// 查询参数解码：`+` 视为空格，再做百分号解码（非法编码返回 nil）
    private static func decode(_ raw: Substring) -> String? {
        raw.replacingOccurrences(of: "+", with: " ").removingPercentEncoding
    }
}
