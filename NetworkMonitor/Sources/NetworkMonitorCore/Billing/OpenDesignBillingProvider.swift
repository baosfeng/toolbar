import Foundation

// MARK: - Open Design 计费 provider

/// Open Design 计费 provider — 编码计划（coding plan）额度 + 工作区用量
///
/// 宿主：`https://amr-api.open-design.ai`，**只认浏览器登录态 Cookie**（无 API Key 体系）：
/// `Cookie: __Secure-better-auth.session_token=<token>`，走 Bearer 一律 401。
///
/// 凭据只填 token 一段，工作区自动发现（`GET /api/v1/workspaces` 取首个 workspaceId 并缓存）。
///
/// 用量接口特性（实测）：
/// - 顶层 `summary` / `totalCount` 是**全范围聚合**，与 `limit` 无关 → 汇总不需要翻页
///   （30 天区间明细可达 1.6 万条，翻页不可接受）
/// - 服务端**不提供服务端分桶**（`granularity` / `group_by` 等参数被忽略）→ 不画柱状图，
///   `supportsTimeSeries = false`；按模型明细走 `?runtime=<name>` 逐模型查 `summary`
/// - `chargeCredits` 全为 0、`listChargedUsd` 只是标价 → 不展示金额，避免虚高花费
public final class OpenDesignBillingProvider: BillingProvider {
    public let id = "open-design"
    public let displayName = "Open Design"
    public let symbolName = "paintpalette"
    public let supportsModelBreakdown = true
    /// 服务端不分桶：UI 隐藏柱状图，只显示指标与按模型明细
    public let supportsTimeSeries = false
    public let credentialHint = "Open Design session token"
    public let credentialPageURL: URL? = URL(string: "https://open-design.ai/")

    /// 官方站点（额度页「获取凭据」跳转与测试注入用）
    public static let defaultBaseURL = URL(string: "https://amr-api.open-design.ai")!

    /// 登录态 Cookie 名（用户从浏览器复制的键名）
    public static let sessionCookieName = "__Secure-better-auth.session_token"

    /// 按模型查用量时的模型数上限（每个模型一次请求，控制限流风险）
    static let modelQueryLimit = 5

    private let baseURL: URL
    private let session: URLSession
    private let logger: LoggingService
    /// workspaceId 缓存（凭据失效时清空，避免长期复用失效结果）
    private let workspaceCache = WorkspaceCache()

    public init(baseURL: URL = OpenDesignBillingProvider.defaultBaseURL,
                session: URLSession = .shared,
                logger: LoggingService = AppContext.shared.logger) {
        self.baseURL = baseURL
        self.session = session
        self.logger = logger
    }

    // MARK: - BillingProvider

    public func fetchBalance(credential: String) async throws -> BillingBalance {
        let token = try Self.normalizedToken(credential)
        let workspaceID = try await resolveWorkspaceID(token: token)
        let request = try makeRequest(path: "/api/v1/workspaces/\(workspaceID)/billing/coding-plan-usage",
                                      query: [], token: token)
        let result = try await perform(request)
        return try Self.decodeBalance(from: result.data)
    }

    public func fetchUsage(range: BillingRange, credential: String) async throws -> BillingUsage {
        let token = try Self.normalizedToken(credential)
        let workspaceID = try await resolveWorkspaceID(token: token)
        let window = range.queryWindow()
        let path = "/api/v1/workspaces/\(workspaceID)/billing/usage"
        let query = [("from", Self.iso8601(window.start)),
                     ("to", Self.iso8601(window.end)),
                     ("limit", "1")]

        let request = try makeRequest(path: path, query: query, token: token)
        let result = try await perform(request)
        let summary = try Self.decodeUsageSummary(from: result.data, requestedRange: range, window: window)

        let groups = try await fetchModelGroups(token: token, path: path, window: window,
                                                runtimes: summary.runtimes)
        return BillingUsage(range: range,
                            granularity: range.granularity,
                            start: window.start,
                            end: window.end,
                            totals: summary.totals,
                            buckets: [],
                            groups: groups)
    }

    // MARK: - 工作区发现

    /// 凭据归一化：允许整条 Cookie 串 / `name=value` / 纯 token 三种形态
    ///
    /// 用户从浏览器复制时常见带前缀与分号的其他 Cookie，这里只取目标键的值。
    public static func normalizedToken(_ credential: String) throws -> String {
        var raw = credential.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { throw BillingError.missingCredential }
        raw = raw.replacingOccurrences(of: "\n", with: " ")
        if raw.lowercased().hasPrefix("cookie:") {
            raw = String(raw.dropFirst("cookie:".count)).trimmingCharacters(in: .whitespaces)
        }
        let segments = raw.split(separator: ";").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        for segment in segments {
            let prefix = sessionCookieName + "="
            if segment.hasPrefix(prefix) {
                let value = String(segment.dropFirst(prefix.count))
                guard !value.isEmpty else { break }
                return value
            }
        }
        // 也接受只贴了 value 的形态
        if raw.contains("=") {
            // 形如 other=value 但键名不匹配：按整串处理会 401，这里直接判为无效
            guard segments.count == 1, !raw.contains("/") else { throw BillingError.missingCredential }
        }
        return raw
    }

    /// 解析 workspaceId（优先缓存）
    private func resolveWorkspaceID(token: String) async throws -> String {
        if let cached = workspaceCache.value(for: token) { return cached }
        let request = try makeRequest(path: "/api/v1/workspaces", query: [], token: token)
        let result = try await perform(request)
        let id = try Self.decodeWorkspaceID(from: result.data)
        workspaceCache.store(id, for: token)
        return id
    }

    // MARK: - 按模型用量

    /// 逐个模型查询全范围汇总（模型数按上限截断，避免请求数失控）
    private func fetchModelGroups(token: String, path: String, window: DateInterval,
                                  runtimes: [String]) async throws -> [BillingGroup] {
        let targets = Array(runtimes.prefix(Self.modelQueryLimit))
        guard !targets.isEmpty else { return [] }
        var groups: [BillingGroup] = []
        for runtime in targets {
            let query = [("from", Self.iso8601(window.start)),
                         ("to", Self.iso8601(window.end)),
                         ("limit", "1"),
                         ("runtime", runtime)]
            do {
                let request = try makeRequest(path: path, query: query, token: token)
                let result = try await perform(request)
                let totals = try Self.decodeUsageTotals(from: result.data)
                groups.append(BillingGroup(name: runtime, metrics: totals))
            } catch let error as BillingError {
                // 模型级查询失败不影响总量展示：跳过该模型并记日志
                logger.warning("Open Design 模型用量查询失败（\(runtime)）：\(error.userMessage)")
            }
        }
        return groups
    }

    // MARK: - 网络

    private struct HTTPResult {
        let data: Data
    }

    private func makeRequest(path: String, query: [(String, String)],
                             token: String) throws -> URLRequest {
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
        // 登录态只认 Cookie：Bearertoken 形式服务端一律 401
        request.setValue("\(Self.sessionCookieName)=\(token)", forHTTPHeaderField: "Cookie")
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
            logger.warning("Open Design 计费请求网络失败: \(error.localizedDescription)")
            throw BillingError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw BillingError.invalidResponse("非 HTTP 响应")
        }
        if (200..<300).contains(http.statusCode) {
            return HTTPResult(data: data)
        }
        let code = Self.errorCode(from: data)
        switch http.statusCode {
        case 400:
            throw BillingError.invalidRequest(Self.errorMessage(from: data))
        case 401:
            // 登录态失效：清掉 workspace 缓存，下次凭据更新后重新发现
            workspaceCache.clear()
            throw BillingError.unauthorized
        case 403:
            let message = code == "workspace_member_required"
                ? "无权访问该工作区，请确认账号仍在成员列表中"
                : Self.errorMessage(from: data)
            throw BillingError.forbidden(message)
        case 429:
            let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap { Double($0) }
            throw BillingError.rateLimited(retryAfter: retry)
        case 500...599:
            throw BillingError.serviceUnavailable(Self.errorMessage(from: data))
        default:
            throw BillingError.invalidResponse("HTTP \(http.statusCode)")
        }
    }

    /// 解析错误响应体 `{"error":"..."}` 或 `{"success":false,"error":{"...":...}}`
    private static func errorMessage(from data: Data) -> String? {
        struct PlainDTO: Decodable { let error: String? }
        if let plain = try? JSONDecoder().decode(PlainDTO.self, from: data), let message = plain.error {
            return message
        }
        return nil
    }

    /// 解析错误码（如 `workspace_member_required`）
    private static func errorCode(from data: Data) -> String? {
        errorMessage(from: data)
    }
}
