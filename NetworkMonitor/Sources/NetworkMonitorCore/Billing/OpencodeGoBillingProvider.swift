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
    /// 统一传输层（由构造参数注入，便于测试替换成替身或指向本地回环）
    private let transport: any HTTPTransport
    /// 当前时刻（旧形态 resetInSec 是相对秒数，需要基准时刻换算出绝对时刻）
    private let now: @Sendable () -> Date

    /// - Parameter logger: 保留签名兼容；出网日志由注入的 transport 输出
    public init(baseURL: URL = OpencodeGoBillingProvider.defaultBaseURL,
                transport: any HTTPTransport = URLSessionHTTPTransport.shared,
                logger: LoggingService = AppContext.shared.logger,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.baseURL = baseURL
        self.transport = transport
        self.now = now
    }

    // MARK: - BillingProvider

    public func fetchBalance(credential: String) async throws -> BillingBalance {
        let data = try await fetch(credential: credential)
        return try Self.decodeBalance(from: data, now: now())
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
    ///
    /// 同时补出 `window`：恢复通知靠它的 cycleID 区分「会话窗口重置」与「周 / 月额度重置」，
    /// 否则只能退回用 resetAt 字符串当周期标识。窗口与 `resetsAt` 复用同一个 Date 实例，
    /// 缺重置字段时窗口为 nil（构造不出「何时重置」的窗口）。
    private static func limit(for raw: OpencodeGoWindowDTO?, window: OpencodeGoWindow,
                              now: Date) -> BillingPercentLimit? {
        guard let raw, let used = raw.usedPercent else { return nil }
        let status = raw.status?.trimmingCharacters(in: .whitespaces).lowercased()
        let rateLimited = status == rateLimitedStatus
        // 已用 → 剩余，并钳制到 0…1：接口偶发负值 / 超过 100 的脏数据
        let remaining = min(max(1 - used / 100, 0), 1)
        let resetsAt = resetDate(raw: raw, now: now)
        return BillingPercentLimit(id: window.limitID,
                                   title: window.title,
                                   remainingFraction: rateLimited ? 0 : remaining,
                                   resetsAt: resetsAt,
                                   badge: rateLimited ? rateLimitedBadge : nil,
                                   window: resetsAt.map { window.quotaWindow(resetsAt: $0) })
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

    /// 一次请求：统一 Endpoint（GET + Bearer + 15s 超时）+ 统一状态码映射
    ///
    /// 与改造前的差异只有超时（20 → 15）：路径 / 头 / 解码 / 错误文案都不变。
    private func fetch(credential: String) async throws -> Data {
        let token = credential.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw BillingError.missingCredential }
        let url = try BillingHTTPMapper.url(base: baseURL, path: Self.usagePath)
        let endpoint = BillingEndpoint.get(url: url,
                                           headers: ["Authorization": "Bearer \(token)"],
                                           label: displayName,
                                           errorText: { HTTPErrorBody.message(from: $0, dialect: .errorOrNested) },
                                           status: Self.mapHTTPError)
        return try await transport.send(endpoint)
    }

    /// HTTP 状态码 → BillingError（纯函数，供测试直接验证映射）
    ///
    /// 401 = Key 无效 / 过期（官方体 `AuthError`）、403 = Key 有效但没有 Go 订阅
    /// （把官方话术翻成能直接照做的中文），其余口径全仓共用。
    public static func mapHTTPError(statusCode: Int, retryAfter: TimeInterval?,
                                    message: String?) -> BillingError {
        BillingHTTPErrorMapper.map(
            statusCode: statusCode, retryAfter: retryAfter, message: message,
            forbidden: .fixed(noSubscriptionMessage))
    }
}
