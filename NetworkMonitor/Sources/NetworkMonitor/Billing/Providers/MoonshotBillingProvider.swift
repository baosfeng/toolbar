import Foundation
import NetworkMonitorCore

// MARK: - Moonshot / Kimi 开放平台余额 provider

/// Moonshot（Kimi）开放平台余额 —— 官方文档化端点，单 API key 认证，纯余额卡
///
/// 端点来源：https://platform.moonshot.cn/docs/api/balance
/// 请求：GET https://api.moonshot.cn/v1/users/me/balance，认证 `Authorization: Bearer <API key>`
/// 响应：`data.available_balance / voucher_balance / cash_balance`（接口不返回币种）
///
/// **区域靠实例区分（不是两个 provider）**：国内站 api.moonshot.cn（CNY）与国际站
/// api.moonshot.ai（USD）字段完全一致，做成同一个 `kindID = moonshot` 的两个命名实例
/// （如 `moonshot::intl`），各自一份凭据与币种；理由：注册表 / 设置页 / 凭据键已按实例
/// 隔离，多一种 provider 类型只会让设置页多一张同构卡片，还得重复实现解析。
///
/// 口径：
/// - 只查余额，没有用量明细 → `supportsUsage = false`；
/// - 没有周期窗口 → 提醒只会有「用尽 / 余额回升」；
/// - 币种由实例构造参数给出（国内 CNY、国际 USD），不猜。
public final class MoonshotBillingProvider: BillingProvider {
    public let id = "moonshot"
    public let displayName = "Moonshot / Kimi"
    public let symbolName = "moon.stars"
    public let supportsModelBreakdown = false
    public let supportsTimeSeries = false
    /// 只有余额接口
    public let supportsUsage = false
    /// 官方未公布该端点限流：5 分钟起刷
    public let minimumRefreshInterval: TimeInterval = 300
    public var credentialHint: String { "Moonshot API Key（" + hostLabel + " 创建）" }
    public var credentialPageURL: URL? { URL(string: credentialPage) }

    /// 凭据页（按站点选国内 / 国际控制台）
    private var credentialPage: String {
        currencyCode == "USD" ? "https://platform.moonshot.ai/console/api-keys"
                              : "https://platform.moonshot.cn/console/api-keys"
    }
    /// 环境变量回退键：厂商原生变量名（`export MOONSHOT_API_KEY=…`）；
    /// 通用键 `BILLING_MOONSHOT_API_KEY` 仍在候选表里作兼容回退。
    public var environmentCredentialKey: String { "MOONSHOT_API_KEY" }

    /// 国内站（默认；国际站用 api.moonshot.ai）
    public static let defaultBaseURL = URL(string: "https://api.moonshot.cn")!
    /// 余额接口路径
    static let balancePath = "/v1/users/me/balance"

    private let baseURL: URL
    /// 站点本位币种（国内站 CNY、国际站 USD）
    private let currencyCode: String
    private let client: BillingHTTPClient
    private let logger: LoggingService

    public init(baseURL: URL = MoonshotBillingProvider.defaultBaseURL,
                currencyCode: String? = nil,
                session: URLSession = .shared,
                logger: LoggingService = AppContext.shared.logger) {
        self.baseURL = baseURL
        // 未显式指定币种时按站点推断：.ai = 国际站 = USD，其余（.cn）= CNY
        self.currencyCode = currencyCode ?? (baseURL.host?.hasSuffix("moonshot.ai") == true ? "USD" : "CNY")
        self.client = BillingHTTPClient(session: session, logger: logger)
        self.logger = logger
    }

    /// 站点名（凭据输入框占位文案用）
    private var hostLabel: String { baseURL.host ?? "platform.moonshot.cn" }

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
            throw MoonshotBillingDecoding.mapHTTPError(statusCode: response.statusCode,
                                                       retryAfter: response.retryAfter,
                                                       message: response.message)
        }
        do {
            return try MoonshotBillingDecoding.decodeBalance(from: response.data,
                                                             currencyCode: currencyCode)
        } catch {
            logger.warning("Moonshot 余额响应解析失败（接口可能已变更）：" + describe(error))
            throw error
        }
    }

    /// 只有余额接口，不提供用量明细
    public func fetchUsage(range: BillingRange, credential: String) async throws -> BillingUsage {
        throw BillingError.invalidRequest("Moonshot 不提供用量明细")
    }

    private func describe(_ error: Error) -> String {
        (error as? BillingError)?.userMessage ?? error.localizedDescription
    }
}