import Foundation
import NetworkMonitorCore

// MARK: - 额度 provider 共用 HTTP 层

/// 非公开端点共用 HTTP 客户端 —— 统一超时、User-Agent、错误体提取与错误收敛
///
/// 三家新 provider（Claude / Codex / Cursor）都打社区实证的非公开端点：
/// 接口可能随时变更，因此这里只做「传输 + 状态码」两件事，解码与错误文案留给各家
/// 的 Core 解码器（可离线单测）。
struct BillingHTTPClient {

    /// 请求超时（非公开端点偶发长响应；15 秒足够且不会长时间占住刷新）
    static let timeout: TimeInterval = 15
    /// User-Agent（部分站点对空 UA 直接 403）
    static let userAgent = "NetworkMonitor/1.0 (macOS)"

    /// 单次响应
    struct Response {
        let data: Data
        let statusCode: Int
        let retryAfter: TimeInterval?
        /// 服务端错误体里的可读文案（尽力提取，拿到什么算什么）
        let message: String?

        var isSuccess: Bool { (200..<300).contains(statusCode) }
    }

    private let session: URLSession
    private let logger: LoggingService

    init(session: URLSession = .shared, logger: LoggingService = AppContext.shared.logger) {
        self.session = session
        self.logger = logger
    }

    /// 发送请求并按状态码装箱（只在传输层失败时抛错）
    ///
    /// - Parameters:
    ///   - request: 已带业务头（Authorization / Cookie / Origin）的请求
    ///   - providerName: 日志用展示名（Claude / Codex / Cursor）
    func send(_ request: URLRequest, providerName: String) async throws -> Response {
        var request = request
        request.timeoutInterval = Self.timeout
        if request.value(forHTTPHeaderField: "User-Agent") == nil {
            request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        }
        if request.value(forHTTPHeaderField: "Accept") == nil {
            request.setValue("application/json", forHTTPHeaderField: "Accept")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            logger.warning("\(providerName) 额度请求网络失败：\(error.localizedDescription)")
            throw BillingError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw BillingError.invalidResponse("非 HTTP 响应")
        }
        let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap { Double($0) }
        return Response(data: data,
                        statusCode: http.statusCode,
                        retryAfter: retryAfter,
                        message: (200..<300).contains(http.statusCode) ? nil : Self.message(from: data))
    }

    /// 从错误响应体里尽力提取可读文案（`error` / `error.message` / `message` / `detail`）
    static func message(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let text = object["error"] as? String { return text }
        if let nested = object["error"] as? [String: Any], let text = nested["message"] as? String {
            return text
        }
        if let text = object["message"] as? String { return text }
        if let text = object["detail"] as? String { return text }
        return nil
    }
}
