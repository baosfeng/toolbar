import Foundation
import NetworkMonitorCore

// MARK: - Cursor 订阅额度 provider

/// Cursor 订阅额度 —— 打 `/api/usage-summary` 取计划额度与计费周期（只查额度）
///
/// 接口性质：cursor.com 控制台前端接口，**非公开、可能失效**；
/// 认证用浏览器 Cookie `WorkosCursorSessionToken`（也接受整条 Cookie 串）。
public final class CursorBillingProvider: BillingProvider {
    public let id = "cursor"
    public let displayName = "Cursor"
    public let symbolName = "cursorarrow.rays"
    public let supportsModelBreakdown = false
    public let supportsTimeSeries = false
    /// 只查额度
    public let supportsUsage = false
    /// 非公开端点：5 分钟起刷
    public let minimumRefreshInterval: TimeInterval = 300
    public let credentialHint = "cursor.com 的 Cookie：WorkosCursorSessionToken 的值（也可粘贴整条 Cookie）"
    public var credentialPageURL: URL? { URL(string: "https://cursor.com/dashboard") }

    /// 站点地址（测试注入本地回环地址）
    public static let defaultBaseURL = URL(string: "https://cursor.com")!
    /// 额度接口路径
    static let usagePath = "/api/usage-summary"
    /// 会话 Cookie 名
    public static let sessionCookieName = "WorkosCursorSessionToken"

    private let baseURL: URL
    private let client: BillingHTTPClient
    private let logger: LoggingService

    public init(baseURL: URL = CursorBillingProvider.defaultBaseURL,
                session: URLSession = .shared,
                logger: LoggingService = AppContext.shared.logger) {
        self.baseURL = baseURL
        self.client = BillingHTTPClient(session: session, logger: logger)
        self.logger = logger
    }

    // MARK: - BillingProvider

    public func fetchBalance(credential: String) async throws -> BillingBalance {
        let cookie = CursorBillingDecoding.cookieHeader(from: credential)
        guard !cookie.isEmpty else { throw BillingError.missingCredential }
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw BillingError.invalidRequest("无效的 provider 地址")
        }
        components.path = Self.usagePath
        guard let url = components.url else { throw BillingError.invalidRequest("无效的请求地址") }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        // 控制台接口对跨站来源比较敏感：带上来源头降低被 Cloudflare 拦的概率
        request.setValue(baseURL.absoluteString, forHTTPHeaderField: "Origin")
        request.setValue(baseURL.appending(path: "/dashboard").absoluteString, forHTTPHeaderField: "Referer")
        let response = try await client.send(request, providerName: displayName)
        guard response.isSuccess else {
            throw CursorBillingDecoding.mapHTTPError(statusCode: response.statusCode,
                                                     retryAfter: response.retryAfter,
                                                     message: response.message)
        }
        do {
            return try CursorBillingDecoding.decodeBalance(from: response.data)
        } catch {
            logger.warning("Cursor 额度响应解析失败（接口可能已变更）：\(describe(error))")
            throw error
        }
    }

    /// 只查额度，不提供用量明细
    public func fetchUsage(range: BillingRange, credential: String) async throws -> BillingUsage {
        throw BillingError.invalidRequest("Cursor 不提供用量明细")
    }

    private func describe(_ error: Error) -> String {
        (error as? BillingError)?.userMessage ?? error.localizedDescription
    }
}
