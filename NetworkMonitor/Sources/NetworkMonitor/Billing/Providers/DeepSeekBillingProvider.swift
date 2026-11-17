import Foundation
import NetworkMonitorCore

// MARK: - DeepSeek 余额 provider

/// DeepSeek 余额 —— 官方文档化端点，单 API key 认证，纯余额卡
///
/// 端点来源：https://api-docs.deepseek.com/api/get-user-balance/
/// 请求：GET https://api.deepseek.com/user/balance，认证 `Authorization: Bearer <API key>`
/// 响应：`balance_infos[].total_balance / granted_balance / topped_up_balance` + `currency`
///
/// 口径：
/// - 只查余额，没有用量明细 → `supportsUsage = false`，状态管理器跳过用量请求；
/// - 没有周期窗口 → 四类提醒里只会有「用尽 / 余额回升」（余额型 provider 的既有口径）；
/// - 金额按响应里的 currency 展示（国内账户是 CNY）。
public final class DeepSeekBillingProvider: BillingProvider {
    public let id = "deepseek"
    public let displayName = "DeepSeek"
    public let symbolName = "brain.head.profile"
    public let supportsModelBreakdown = false
    public let supportsTimeSeries = false
    /// 只有余额接口
    public let supportsUsage = false
    /// 官方未公布该端点限流：5 分钟起刷，少打接口
    public let minimumRefreshInterval: TimeInterval = 300
    public let credentialHint = "DeepSeek API Key（platform.deepseek.com 创建）"
    public var credentialPageURL: URL? { URL(string: "https://platform.deepseek.com/api_keys") }
    // 环境变量回退键用协议默认口径 BILLING_DEEPSEEK_API_KEY：
    // 注册表里存的是 BillingProviderInstance，它统一按「实例 id」推导键，
    // 这里若声明厂商自带变量名（DEEPSEEK_API_KEY）实际不会被读到。

    /// 站点地址（测试注入本地回环地址）
    public static let defaultBaseURL = URL(string: "https://api.deepseek.com")!
    /// 余额接口路径
    static let balancePath = "/user/balance"

    private let baseURL: URL
    private let client: BillingHTTPClient
    private let logger: LoggingService

    public init(baseURL: URL = DeepSeekBillingProvider.defaultBaseURL,
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
        components.path = Self.balancePath
        guard let url = components.url else { throw BillingError.invalidRequest("无效的请求地址") }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        let response = try await client.send(request, providerName: displayName)
        guard response.isSuccess else {
            throw DeepSeekBillingDecoding.mapHTTPError(statusCode: response.statusCode,
                                                       retryAfter: response.retryAfter,
                                                       message: response.message)
        }
        do {
            return try DeepSeekBillingDecoding.decodeBalance(from: response.data)
        } catch {
            logger.warning("DeepSeek 余额响应解析失败（接口可能已变更）：" + describe(error))
            throw error
        }
    }

    /// 只有余额接口，不提供用量明细
    public func fetchUsage(range: BillingRange, credential: String) async throws -> BillingUsage {
        throw BillingError.invalidRequest("DeepSeek 不提供用量明细")
    }

    private func describe(_ error: Error) -> String {
        (error as? BillingError)?.userMessage ?? error.localizedDescription
    }
}