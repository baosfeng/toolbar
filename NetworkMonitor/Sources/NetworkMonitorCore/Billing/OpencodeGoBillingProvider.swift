import Foundation

// MARK: - OpenCode Go 计费 provider

/// OpenCode Go 计费 provider — 订阅额度三窗口（5 小时 / 每周 / 每月），只查额度
///
/// 接口：GET https://opencode.ai/zen/go/v1/usage
/// 鉴权：Authorization: Bearer sk-…（Go API Key，与推理同一把）
///
/// 口径：
/// - 接口给的是已用百分比，App 内统一存剩余，换算与钳制都在 provider 内完成
/// - status = rate-limited 表示该窗口耗尽：剩余置 0（让阈值提醒生效）并标「已限流」
/// - 没有余额接口、没有用量明细 → supportsUsage = false，状态管理器据此跳过用量请求
/// - 官方未公布该接口限流 → minimumRefreshInterval = 300（5 分钟），少打接口
/// - 响应结构按新旧两套键名双兼容实现（字段见 OpencodeGoBillingDTOs.swift）
public final class OpencodeGoBillingProvider: BillingProvider {
    public let id = "opencode-go"
    public let displayName = "OpenCode Go"
    public let symbolName = "terminal"
    public let supportsModelBreakdown = false
    public let supportsTimeSeries = false
    /// 没有用量明细：UI 隐藏用量区，状态管理器不发起用量请求
    public let supportsUsage = false
    /// 官方未公布该接口限流：5 分钟起刷，避免撞未知限流后整块失败
    public let minimumRefreshInterval: TimeInterval = 300
    public let credentialHint = "OpenCode Go API Key"
    /// 控制台地址（配置态「获取凭据」跳转目标）
    public var credentialPageURL: URL? { URL(string: "https://opencode.ai/") }

    /// 站点地址（测试注入本地回环地址）
    public static let defaultBaseURL = URL(string: "https://opencode.ai")!
    /// 额度接口路径
    static let usagePath = "/zen/go/v1/usage"
    /// 403 用户话术 —— 官方原话是 OpenCode Go subscription required.
    public static let noSubscriptionMessage = "该 Key 没有 OpenCode Go 订阅"
    /// 已耗尽窗口的角标
    public static let rateLimitedBadge = "已限流"
    /// 已耗尽状态取值（比较前统一小写）
    static let rateLimitedStatus = "rate-limited"

    private let baseURL: URL
    private let session: URLSession
    private let logger: LoggingService
    /// 当前时刻（旧形态 resetInSec 是相对秒数，需要基准时刻换算出绝对时刻）
    private let now: @Sendable () -> Date

    public init(baseURL: URL = OpencodeGoBillingProvider.defaultBaseURL,
                session: URLSession = .shared,
                logger: LoggingService = AppContext.shared.logger,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.baseURL = baseURL
        self.session = session
        self.logger = logger
        self.now = now
    }

    // MARK: - BillingProvider

    public func fetchBalance(credential: String) async throws -> BillingBalance {
        let request = try makeRequest(credential: credential)
        let result = try await perform(request)
        return try Self.decodeBalance(from: result.data, now: now())
    }

    /// 用量明细：OpenCode Go 不提供 —— 恒抛 invalidRequest
    ///
    /// 调用方（BillingMonitor）按 supportsUsage == false 短路，正常流程不会走到这里；
    /// 这里抛错而不是返回空用量，是为了让「漏判能力位」在开发期立刻暴露。
    public func fetchUsage(range: BillingRange, credential: String) async throws -> BillingUsage {
        throw BillingError.invalidRequest("OpenCode Go 不提供用量明细")
    }

    // MARK: - 解码（public 供测试直接验证映射）

    /// 解析额度响应：三窗口各自映射为一条百分比限额
    ///
    /// 缺哪个窗口就少一条，三条全缺才报 invalidResponse —— 接口改形态时退化为
    /// 「响应解析失败」提示，而不是崩溃或整块空白。
    public static func decodeBalance(from data: Data, now: Date = Date()) throws -> BillingBalance {
        let decoder = JSONDecoder()
        // 新形态把三窗口包在 usage 里，旧形态直接平铺在顶层，两处都试
        let wrapped = try? decoder.decode(OpencodeGoUsageResponseDTO.self, from: data)
        let flat = try? decoder.decode(OpencodeGoWindowScopeDTO.self, from: data)
        guard let scope = wrapped?.usage ?? flat else {
            throw BillingError.invalidResponse("响应不是合法的额度 JSON")
        }
        let limits = OpencodeGoWindow.allCases.compactMap { window in
            limit(for: scope.window(for: window), window: window, now: now)
        }
        guard !limits.isEmpty else {
            throw BillingError.invalidResponse("响应里没有额度窗口")
        }
        return BillingBalance(included: nil, purchasedUSD: nil, percentLimits: limits)
    }

    /// 单窗口映射：已用百分比 → 剩余比例（已限流强制归零并加角标）
    private static func limit(for raw: OpencodeGoWindowDTO?, window: OpencodeGoWindow,
                              now: Date) -> BillingPercentLimit? {
        guard let raw, let used = raw.usedPercent else { return nil }
        let status = raw.status?.trimmingCharacters(in: .whitespaces).lowercased()
        let rateLimited = status == rateLimitedStatus
        // 已用 → 剩余，并钳制到 0…1：接口偶发负值 / 超过 100 的脏数据
        let remaining = min(max(1 - used / 100, 0), 1)
        return BillingPercentLimit(id: window.limitID,
                                   title: window.title,
                                   remainingFraction: rateLimited ? 0 : remaining,
                                   resetsAt: resetDate(raw: raw, now: now),
                                   badge: rateLimited ? rateLimitedBadge : nil)
    }

    /// 重置时刻：新形态是 RFC3339 绝对时刻，旧形态是相对秒数（按基准时刻换算）
    private static func resetDate(raw: OpencodeGoWindowDTO, now: Date) -> Date? {
        if let text = raw.resetsAt, let date = parseISO8601(text) { return date }
        guard let seconds = raw.resetInSec else { return nil }
        return now.addingTimeInterval(seconds)
    }

    /// ISO8601 解析（兼容带 / 不带小数秒）
    static func parseISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string)
    }

    // MARK: - 网络

    /// 单次 HTTP 结果
    private struct HTTPResult {
        let data: Data
    }

    private func makeRequest(credential: String) throws -> URLRequest {
        let token = credential.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw BillingError.missingCredential }
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw BillingError.invalidRequest("无效的 provider 地址")
        }
        components.path = Self.usagePath
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

    /// 执行请求并按 HTTP 状态映射为 BillingError
    private func perform(_ request: URLRequest) async throws -> HTTPResult {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            logger.warning("OpenCode Go 计费请求网络失败: \(error.localizedDescription)")
            throw BillingError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw BillingError.invalidResponse("非 HTTP 响应")
        }
        if (200..<300).contains(http.statusCode) {
            return HTTPResult(data: data)
        }
        throw Self.mapHTTPError(statusCode: http.statusCode,
                                retryAfter: http.value(forHTTPHeaderField: "Retry-After").flatMap { Double($0) },
                                message: Self.errorMessage(from: data))
    }

    /// HTTP 状态码 → BillingError（纯函数，供测试直接验证映射）
    public static func mapHTTPError(statusCode: Int, retryAfter: TimeInterval?,
                                    message: String?) -> BillingError {
        switch statusCode {
        case 400:
            return .invalidRequest(message)
        case 401:
            // Key 无效 / 过期（官方体：{"type":"error","error":{"type":"AuthError",...}}）
            return .unauthorized
        case 403:
            // Key 有效但没有 Go 订阅：把官方话术翻成用户能直接照做的中文
            return .forbidden(noSubscriptionMessage)
        case 429:
            return .rateLimited(retryAfter: retryAfter)
        case 500...599:
            return .serviceUnavailable(message)
        default:
            return .invalidResponse("HTTP \(statusCode)")
        }
    }

    /// 解析错误响应体：兼容 {"error":"..."} 与 {"error":{"message":"..."}} 两种形态
    private static func errorMessage(from data: Data) -> String? {
        struct PlainDTO: Decodable { let error: String? }
        struct NestedTextDTO: Decodable { let message: String? }
        struct NestedDTO: Decodable { let error: NestedTextDTO? }

        if let plain = try? JSONDecoder().decode(PlainDTO.self, from: data),
           let message = plain.error, !message.isEmpty {
            return message
        }
        if let nested = try? JSONDecoder().decode(NestedDTO.self, from: data) {
            return nested.error?.message
        }
        return nil
    }
}
