import Foundation
import NetworkMonitorCore

// MARK: - Claude（Anthropic）订阅额度 provider

/// Claude 订阅额度 —— 打 `/api/oauth/usage` 取 5 小时 / 每周窗口（只查额度）
///
/// 接口性质：Claude Code 客户端自用的 OAuth 端点，**非公开、可能失效**；
/// 因此刷新间隔 300 秒起步，失败时只回报错误、保留上次成功数据（由状态管理器保证）。
public final class ClaudeBillingProvider: BillingProvider {
    public let id = "claude"
    public let displayName = "Claude"
    public let symbolName = "sparkles"
    public let supportsModelBreakdown = false
    public let supportsTimeSeries = false
    /// 只查额度：没有公开的用量明细端点
    public let supportsUsage = false
    /// 非公开端点，官方未公布限流：5 分钟起刷
    public let minimumRefreshInterval: TimeInterval = 300
    public let credentialHint = "Claude OAuth access token（claude /login 后的 token，或 Bearer 串）"
    public var credentialPageURL: URL? { URL(string: "https://claude.ai/settings/usage") }

    /// 站点地址（测试注入本地回环地址）
    public static let defaultBaseURL = URL(string: "https://api.anthropic.com")!
    /// 额度接口路径
    static let usagePath = "/api/oauth/usage"
    /// 接口要求的 beta 标识
    static let betaHeader = "oauth-2025-04-20"

    private let baseURL: URL
    private let client: BillingHTTPClient
    private let logger: LoggingService

    public init(baseURL: URL = ClaudeBillingProvider.defaultBaseURL,
                session: URLSession = .shared,
                logger: LoggingService = AppContext.shared.logger) {
        self.baseURL = baseURL
        self.client = BillingHTTPClient(session: session, logger: logger)
        self.logger = logger
    }

    // MARK: - BillingProvider

    public func fetchBalance(credential: String) async throws -> BillingBalance {
        let token = BillingCredentialNormalizer.token(credential)
        guard !token.isEmpty else { throw BillingError.missingCredential }
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw BillingError.invalidRequest("无效的 provider 地址")
        }
        components.path = Self.usagePath
        components.queryItems = [URLQueryItem(name: "cedar_ember", value: "1")]
        guard let url = components.url else { throw BillingError.invalidRequest("无效的请求地址") }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.betaHeader, forHTTPHeaderField: "anthropic-beta")
        let response = try await client.send(request, providerName: displayName)
        guard response.isSuccess else {
            throw ClaudeBillingDecoding.mapHTTPError(statusCode: response.statusCode,
                                                    retryAfter: response.retryAfter,
                                                    message: response.message)
        }
        do {
            return try ClaudeBillingDecoding.decodeBalance(from: response.data)
        } catch {
            logger.warning("Claude 额度响应解析失败（接口可能已变更）：\(describe(error))")
            throw error
        }
    }

    /// 只查额度，不提供用量明细（漏判能力位时立刻暴露）
    public func fetchUsage(range: BillingRange, credential: String) async throws -> BillingUsage {
        throw BillingError.invalidRequest("Claude 不提供用量明细")
    }

    private func describe(_ error: Error) -> String {
        (error as? BillingError)?.userMessage ?? error.localizedDescription
    }
}
