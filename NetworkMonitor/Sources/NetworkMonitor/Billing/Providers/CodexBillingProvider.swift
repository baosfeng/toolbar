import Foundation
import NetworkMonitorCore

// MARK: - Codex（OpenAI 订阅额度）provider

/// Codex 订阅额度 —— 打 `/backend-api/wham/usage` 取 5 小时 / 每周窗口（只查额度）
///
/// 接口性质：ChatGPT 后端自用端点，**非公开、可能失效**；
/// token 取自 `~/.codex/auth.json` 的 access_token（与 Codex CLI 同一把）。
public final class CodexBillingProvider: BillingProvider {
    public let id = "codex"
    public let displayName = "Codex"
    public let symbolName = "terminal.fill"
    public let supportsModelBreakdown = false
    public let supportsTimeSeries = false
    /// 只查额度
    public let supportsUsage = false
    /// 非公开端点：5 分钟起刷
    public let minimumRefreshInterval: TimeInterval = 300
    public let credentialHint = "Codex OAuth token（~/.codex/auth.json 里的 access_token）"
    public var credentialPageURL: URL? { URL(string: "https://chatgpt.com/codex/settings/usage") }

    /// 站点地址（测试注入本地回环地址）
    public static let defaultBaseURL = URL(string: "https://chatgpt.com")!
    /// 额度接口路径
    static let usagePath = "/backend-api/wham/usage"

    private let baseURL: URL
    private let client: BillingHTTPClient
    private let logger: LoggingService

    public init(baseURL: URL = CodexBillingProvider.defaultBaseURL,
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
        guard let url = components.url else { throw BillingError.invalidRequest("无效的请求地址") }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let response = try await client.send(request, providerName: displayName)
        guard response.isSuccess else {
            throw CodexBillingDecoding.mapHTTPError(statusCode: response.statusCode,
                                                    retryAfter: response.retryAfter,
                                                    message: response.message)
        }
        do {
            return try CodexBillingDecoding.decodeBalance(from: response.data)
        } catch {
            logger.warning("Codex 额度响应解析失败（接口可能已变更）：\(describe(error))")
            throw error
        }
    }

    /// 只查额度，不提供用量明细
    public func fetchUsage(range: BillingRange, credential: String) async throws -> BillingUsage {
        throw BillingError.invalidRequest("Codex 不提供用量明细")
    }

    private func describe(_ error: Error) -> String {
        (error as? BillingError)?.userMessage ?? error.localizedDescription
    }
}
