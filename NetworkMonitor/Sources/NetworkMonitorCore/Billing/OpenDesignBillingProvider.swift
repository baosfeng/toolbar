import Foundation

// MARK: - Open Design 计费 provider

/// Open Design 计费 provider — 编码计划（coding plan）额度 + 工作区用量
///
/// 宿主：`https://amr-api.open-design.ai`，**只认浏览器登录态 Cookie**（无 API Key 体系）：
/// `Cookie: __Secure-better-auth.session_token=<token>`，走 Bearer 一律 401。
///
/// 凭据只填 token 一段，工作区自动发现（`GET /api/v1/workspaces` 取首个 workspaceId 并缓存）。
///
/// **只查额度**（`supportsUsage = false`）：`/billing/usage` 自 2026-11 起实测**不再返回顶层聚合**，
/// 详见下方「用量为何下线」与 docs/踩坑/接口/open-design-额度接口-鉴权与聚合.md。
///
/// 额度接口特性（实测，`/billing/coding-plan-usage`）：
/// - 返回 `eligible` / `tier` / `windows[]`（每窗口 `usedCredits` / `limitCredits` / `remainingCredits` /
///   `resetsAt` / `durationSeconds`），据此换算成百分比限额；金额维度不存在。
/// - 服务端不分桶、无金额扣费（`chargeCredits` 恒 0，`listChargedUsd` 只是标价）。
public final class OpenDesignBillingProvider: BillingProvider {
    public let id = "open-design"
    public let displayName = "Open Design"
    public let symbolName = "paintpalette"
    public let supportsModelBreakdown = true
    /// 服务端不分桶（且用量已下线）：UI 隐藏柱状图
    public let supportsTimeSeries = false
    /// 服务端只接受最近 7 天的用量窗口（30 天跨度直接 400）
    public let supportedUsageRanges: [BillingRange] = [.last24Hours, .last7Days]
    public let credentialHint = "Open Design session token"
    public let credentialPageURL: URL? = URL(string: "https://open-design.ai/")

    /// 官方站点（额度页「获取凭据」跳转与测试注入用）
    public static let defaultBaseURL = URL(string: "https://amr-api.open-design.ai")!

    /// 登录态 Cookie 名（用户从浏览器复制的键名）
    public static let sessionCookieName = "__Secure-better-auth.session_token"


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

    // MARK: - 能力位

    /// 用量明细不可得 —— 与 OpenCode Go 同一处置口径（只查额度的 provider 一律关掉用量）
    ///
    /// 实测（2026-11-13，本机真实凭据）：`GET /billing/usage?from=&to=&limit=N` 的响应顶层只剩
    /// `entries` / `hasMore` / `nextCursor` / `workspaceId`，**`summary` 与 `totalCount` 双双消失**
    /// （`aggregate` / `includeSummary` / `granularity` 等参数一律被忽略）。于是：
    /// - 按旧契约解码必然 keyNotFound（面板显示「响应解析失败：The data couldn't be read because it is missing」）；
    /// - 想靠翻页自己聚合也不行：`limit` 上限 100（200 起直接 400），7 天窗口 1.6 万条要 160+ 页。
    /// 结论：这台服务只可信地提供额度。关掉用量后，状态管理器不再发这个必然失败的请求，
    /// 面板也不再留一条无法自愈的错误条。
    public let supportsUsage = false

    // MARK: - BillingProvider

    public func fetchBalance(credential: String) async throws -> BillingBalance {
        let token = try Self.normalizedToken(credential)
        let workspaceID = try await resolveWorkspaceID(token: token)
        let request = try makeRequest(path: "/api/v1/workspaces/\(workspaceID)/billing/coding-plan-usage",
                                      query: [], token: token)
        let result = try await perform(request)
        return try Self.decodeBalance(from: result.data)
    }

    /// 用量查询 —— 保留协议实现，但服务端已不再提供可用的聚合汇总
    ///
    /// `supportsUsage = false` 后 `BillingMonitor` 不会调用本方法；这里显式抛可读错误，
    /// 避免未来误开能力位时拿着一份「只有 100 条明细」的数据去充当全范围汇总。
    public func fetchUsage(range: BillingRange, credential: String) async throws -> BillingUsage {
        throw BillingError.invalidRequest("Open Design 已停止提供用量汇总，仅支持额度查询")
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
