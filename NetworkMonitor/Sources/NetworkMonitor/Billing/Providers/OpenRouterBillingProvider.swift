import Foundation
import NetworkMonitorCore

// MARK: - OpenRouter 额度 provider

/// OpenRouter 账户额度 —— 官方文档化端点，单 API key 认证
///
/// 端点来源：https://openrouter.ai/docs/api-reference/limits
/// 请求：GET https://openrouter.ai/api/v1/key，认证 `Authorization: Bearer <API key>`
/// 响应：`data.limit / limit_remaining / limit_reset / usage`；`limit` 为空表示无上限。
///
/// 口径：
/// - 余额 = `limit_remaining`（接口缺失时用 `limit - usage` 兜底），只渲染一张余额卡；
/// - `limit` 为空（无上限 Key）→ 一条「无限制」额度行，不显示 0；
/// - 只做 `/api/v1/key`：`/api/v1/credits` 需要 Management key，本批不接；
/// - 只查额度，没有用量明细 → `supportsUsage = false`。
public final class OpenRouterBillingProvider: BillingProvider {
    public let id = "openrouter"
    public let displayName = "OpenRouter"
    public let symbolName = "arrow.triangle.branch"
    public let supportsModelBreakdown = false
    public let supportsTimeSeries = false
    /// 只有 Key 额度接口
    public let supportsUsage = false
    /// 官方未在文档里公布该端点限流：5 分钟起刷
    public let minimumRefreshInterval: TimeInterval = 300
    public let credentialHint = "OpenRouter API Key（openrouter.ai/keys 创建）"
    public var credentialPageURL: URL? { URL(string: "https://openrouter.ai/keys") }
    /// 环境变量回退键：厂商原生变量名（`export OPENROUTER_API_KEY=…`）；
    /// 通用键 `BILLING_OPENROUTER_API_KEY` 仍在候选表里作兼容回退。
    public var environmentCredentialKey: String { "OPENROUTER_API_KEY" }

    /// 站点地址（测试注入本地回环地址）
    public static let defaultBaseURL = URL(string: "https://openrouter.ai")!
    /// Key 额度接口路径
    static let keyPath = "/api/v1/key"

    private let baseURL: URL
    private let client: BillingHTTPClient
    private let logger: LoggingService

    public init(baseURL: URL = OpenRouterBillingProvider.defaultBaseURL,
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
        components.path = Self.keyPath
        guard let url = components.url else { throw BillingError.invalidRequest("无效的请求地址") }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        let response = try await client.send(request, providerName: displayName)
        guard response.isSuccess else {
            throw OpenRouterBillingDecoding.mapHTTPError(statusCode: response.statusCode,
                                                         retryAfter: response.retryAfter,
                                                         message: response.message)
        }
        do {
            return try OpenRouterBillingDecoding.decodeBalance(from: response.data)
        } catch {
            logger.warning("OpenRouter 额度响应解析失败（接口可能已变更）：" + describe(error))
            throw error
        }
    }

    /// 只有 Key 额度接口，不提供用量明细
    public func fetchUsage(range: BillingRange, credential: String) async throws -> BillingUsage {
        throw BillingError.invalidRequest("OpenRouter 不提供用量明细")
    }

    private func describe(_ error: Error) -> String {
        (error as? BillingError)?.userMessage ?? error.localizedDescription
    }
}