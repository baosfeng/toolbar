import Foundation

// MARK: - 请求地址构造

/// 请求地址构造 —— baseURL + path + query 的唯一一份
///
/// 改造前 Ollama / OpenDesign / OpencodeGo / Transfer 各写了一遍 URLComponents；
/// 这里只做「拼 URL」，不碰请求头与请求体（那是 Endpoint 的事）。
///
/// 失败分两种，调用方据此给出与改造前一致的文案：
/// - invalidBase：baseURL 本身拆不出组件（改造前的「无效的 provider 地址」）
/// - invalidURL：拼完仍得不到 URL（改造前的「无效的请求地址」）
public enum HTTPURLBuilder {
    public enum Failure: Error, Equatable, Sendable {
        case invalidBase
        case invalidURL
    }

    public static func url(base: URL, path: String, query: [(String, String)] = []) throws -> URL {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw Failure.invalidBase
        }
        components.path = path
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        }
        guard let url = components.url else { throw Failure.invalidURL }
        return url
    }
}
