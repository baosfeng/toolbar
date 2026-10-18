import Foundation

// MARK: - Ollama 计费 provider

/// Ollama 云端计费 provider — 余额 `/api/balance` + 用量 `/api/usage`
///
/// 文档：
/// - https://docs.ollama.com/api/balance
/// - https://docs.ollama.com/api/cloud-usage
///
/// 限流：10 次/分钟/用户（跨 API Key 与设备共享），429 时带 `Retry-After` 秒数，
/// 调用方（BillingMonitor）据此退避，不在 provider 内部重试。
public final class OllamaBillingProvider: BillingProvider {
    public let id = "ollama"
    public let displayName = "Ollama"
    public let symbolName = "cloud"
    public let supportsModelBreakdown = true
    public let credentialHint = "Ollama API Key"
    /// Ollama 官方环境变量名（命令行调试时可直接 `export OLLAMA_API_KEY=...`）
    public var environmentCredentialKey: String { "OLLAMA_API_KEY" }

    /// 云端地址（测试注入本地回环地址）
    public static let defaultBaseURL = URL(string: "https://ollama.com")!

    private let baseURL: URL
    private let session: URLSession
    private let logger: LoggingService

    public init(baseURL: URL = OllamaBillingProvider.defaultBaseURL,
                session: URLSession = .shared,
                logger: LoggingService = AppContext.shared.logger) {
        self.baseURL = baseURL
        self.session = session
        self.logger = logger
    }

    // MARK: - BillingProvider

    public func fetchBalance(credential: String) async throws -> BillingBalance {
        let request = try makeRequest(path: "/api/balance", query: [], credential: credential)
        let result = try await perform(request)
        return try Self.decodeBalance(from: result.data)
    }

    public func fetchUsage(range: BillingRange, credential: String) async throws -> BillingUsage {
        var query: [(String, String)] = [("range", range.queryValue)]
        if supportsModelBreakdown {
            query.append(("group_by", "model"))
        }
        let request = try makeRequest(path: "/api/usage", query: query, credential: credential)
        let result = try await perform(request)
        return try Self.decodeUsage(from: result.data, requestedRange: range)
    }

    // MARK: - 网络

    /// 单次 HTTP 结果
    private struct HTTPResult {
        let data: Data
        let statusCode: Int
    }

    private func makeRequest(path: String, query: [(String, String)],
                             credential: String) throws -> URLRequest {
        let token = credential.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw BillingError.missingCredential }
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw BillingError.invalidRequest("无效的 provider 地址")
        }
        components.path = path
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        }
        guard let url = components.url else {
            throw BillingError.invalidRequest("无效的请求地址")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    /// 执行请求并按 HTTP 状态映射为 `BillingError`
    private func perform(_ request: URLRequest) async throws -> HTTPResult {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            logger.warning("计费请求网络失败: \(error.localizedDescription)")
            throw BillingError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw BillingError.invalidResponse("非 HTTP 响应")
        }
        if (200..<300).contains(http.statusCode) {
            return HTTPResult(data: data, statusCode: http.statusCode)
        }
        let message = Self.errorMessage(from: data)
        switch http.statusCode {
        case 400:
            throw BillingError.invalidRequest(message)
        case 401:
            throw BillingError.unauthorized
        case 403:
            throw BillingError.forbidden(message)
        case 429:
            let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap { Double($0) }
            throw BillingError.rateLimited(retryAfter: retry)
        case 500...599:
            throw BillingError.serviceUnavailable(message)
        default:
            throw BillingError.invalidResponse("HTTP \(http.statusCode)")
        }
    }

    /// 解析错误响应体 `{"error": "..."}`
    private static func errorMessage(from data: Data) -> String? {
        struct ErrorDTO: Decodable { let error: String? }
        return (try? JSONDecoder().decode(ErrorDTO.self, from: data))?.error
    }

    // MARK: - 解码（public 供测试与调试直接验证映射）

    /// 解析余额响应
    public static func decodeBalance(from data: Data) throws -> BillingBalance {
        let dto: BalanceDTO
        do {
            dto = try JSONDecoder().decode(BalanceDTO.self, from: data)
        } catch {
            throw BillingError.invalidResponse(error.localizedDescription)
        }

        var included: BillingIncludedBalance?
        if let raw = dto.included, let remaining = raw.balanceUSD, let allowance = raw.allowanceUSD {
            var period: BillingPeriod?
            if let rawPeriod = raw.period,
               let start = parseISO8601(rawPeriod.from),
               let end = parseISO8601(rawPeriod.until) {
                period = BillingPeriod(start: start, end: end)
            }
            included = BillingIncludedBalance(remainingUSD: remaining,
                                              allowanceUSD: allowance,
                                              period: period)
        }

        var limits: [BillingPercentLimit] = []
        if let session = dto.included?.session, let percent = session.remainingPercent {
            limits.append(BillingPercentLimit(id: "session",
                                              title: "会话",
                                              remainingFraction: percent / 100,
                                              resetsAt: session.resetsAt.flatMap(parseISO8601)))
        }
        if let weekly = dto.included?.weekly, let percent = weekly.remainingPercent {
            limits.append(BillingPercentLimit(id: "weekly",
                                              title: "每周",
                                              remainingFraction: percent / 100,
                                              resetsAt: weekly.resetsAt.flatMap(parseISO8601)))
        }

        return BillingBalance(included: included,
                              purchasedUSD: dto.purchased?.balanceUSD,
                              percentLimits: limits)
    }

    /// 解析用量响应
    public static func decodeUsage(from data: Data, requestedRange: BillingRange) throws -> BillingUsage {
        let dto: UsageDTO
        do {
            dto = try JSONDecoder().decode(UsageDTO.self, from: data)
        } catch {
            throw BillingError.invalidResponse(error.localizedDescription)
        }
        guard let start = parseISO8601(dto.from), let end = parseISO8601(dto.until) else {
            throw BillingError.invalidResponse("时间范围无法解析")
        }
        let granularity: BillingGranularity = dto.granularity == "hour" ? .hour : .day
        let buckets = try dto.buckets.map { bucket -> BillingBucket in
            guard let bucketStart = parseISO8601(bucket.from),
                  let bucketEnd = parseISO8601(bucket.until) else {
                throw BillingError.invalidResponse("分桶时间无法解析")
            }
            return BillingBucket(start: bucketStart,
                                 end: bucketEnd,
                                 isPartial: bucket.partial ?? false,
                                 metrics: bucket.metrics,
                                 groups: bucket.groups?.map(\.billingGroup) ?? [])
        }
        return BillingUsage(range: requestedRange,
                            granularity: granularity,
                            start: start,
                            end: end,
                            totals: dto.totals.metrics,
                            buckets: buckets,
                            groups: dto.totals.groups?.map(\.billingGroup) ?? [])
    }

    /// ISO8601 解析（兼容带/不带小数秒）
    static func parseISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string)
    }
}

// MARK: - 响应 DTO（字段名与 API 原样一致）

private struct BalanceDTO: Decodable {
    struct Period: Decodable {
        let from: String
        let until: String
    }

    struct LegacyLimitDTO: Decodable {
        let remainingPercent: Double?
        let resetsAt: String?

        enum CodingKeys: String, CodingKey {
            case remainingPercent = "remaining_percent"
            case resetsAt = "resets_at"
        }
    }

    struct IncludedDTO: Decodable {
        let balanceUSD: Double?
        let allowanceUSD: Double?
        let period: Period?
        let session: LegacyLimitDTO?
        let weekly: LegacyLimitDTO?

        enum CodingKeys: String, CodingKey {
            case balanceUSD = "balance_usd"
            case allowanceUSD = "allowance_usd"
            case period, session, weekly
        }
    }

    struct PurchasedDTO: Decodable {
        let balanceUSD: Double?

        enum CodingKeys: String, CodingKey {
            case balanceUSD = "balance_usd"
        }
    }

    let included: IncludedDTO?
    let purchased: PurchasedDTO?
}

private struct UsageDTO: Decodable {
    struct GroupDTO: Decodable {
        let model: String
        let requestCount: Int
        let usageUSD: Double?
        let inputTokens: Int?
        let cachedInputTokens: Int?
        let outputTokens: Int?

        enum CodingKeys: String, CodingKey {
            case model
            case requestCount = "request_count"
            case usageUSD = "usage_usd"
            case inputTokens = "input_tokens"
            case cachedInputTokens = "cached_input_tokens"
            case outputTokens = "output_tokens"
        }

        var billingGroup: BillingGroup {
            BillingGroup(name: model,
                         metrics: BillingMetrics(requestCount: requestCount,
                                                 usageUSD: usageUSD,
                                                 inputTokens: inputTokens,
                                                 cachedInputTokens: cachedInputTokens,
                                                 outputTokens: outputTokens))
        }
    }

    struct MetricsDTO: Decodable {
        let requestCount: Int
        let usageUSD: Double?
        let inputTokens: Int?
        let cachedInputTokens: Int?
        let outputTokens: Int?
        let groups: [GroupDTO]?

        enum CodingKeys: String, CodingKey {
            case requestCount = "request_count"
            case usageUSD = "usage_usd"
            case inputTokens = "input_tokens"
            case cachedInputTokens = "cached_input_tokens"
            case outputTokens = "output_tokens"
            case groups
        }

        var metrics: BillingMetrics {
            BillingMetrics(requestCount: requestCount,
                           usageUSD: usageUSD,
                           inputTokens: inputTokens,
                           cachedInputTokens: cachedInputTokens,
                           outputTokens: outputTokens)
        }
    }

    struct BucketDTO: Decodable {
        let from: String
        let until: String
        let partial: Bool?
        let requestCount: Int
        let usageUSD: Double?
        let inputTokens: Int?
        let cachedInputTokens: Int?
        let outputTokens: Int?
        let groups: [GroupDTO]?

        enum CodingKeys: String, CodingKey {
            case from, until, partial, groups
            case requestCount = "request_count"
            case usageUSD = "usage_usd"
            case inputTokens = "input_tokens"
            case cachedInputTokens = "cached_input_tokens"
            case outputTokens = "output_tokens"
        }

        var metrics: BillingMetrics {
            BillingMetrics(requestCount: requestCount,
                           usageUSD: usageUSD,
                           inputTokens: inputTokens,
                           cachedInputTokens: cachedInputTokens,
                           outputTokens: outputTokens)
        }
    }

    let range: String
    let granularity: String
    let from: String
    let until: String
    let totals: MetricsDTO
    let buckets: [BucketDTO]
}
