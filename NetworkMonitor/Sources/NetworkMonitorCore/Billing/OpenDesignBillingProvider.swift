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
    /// 统一传输层（由构造参数注入，便于测试替换成替身或指向本地回环）
    private let transport: any HTTPTransport
    /// workspaceId 缓存（凭据失效时清空，避免长期复用失效结果）
    private let workspaceCache = WorkspaceCache()

    /// - Parameter logger: 保留签名兼容；出网日志由注入的 transport 输出
    public init(baseURL: URL = OpenDesignBillingProvider.defaultBaseURL,
                transport: any HTTPTransport = URLSessionHTTPTransport.shared,
                logger: LoggingService = AppContext.shared.logger) {
        self.baseURL = baseURL
        self.transport = transport
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
        let data = try await fetch(path: "/api/v1/workspaces/\(workspaceID)/billing/coding-plan-usage",
                                  query: [], token: token)
        return try Self.decodeBalance(from: data)
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
        let data = try await fetch(path: "/api/v1/workspaces", query: [], token: token)
        let id = try Self.decodeWorkspaceID(from: data)
        workspaceCache.store(id, for: token)
        return id
    }
    // MARK: - 网络

    /// 一次请求：统一 Endpoint（GET + 登录态 Cookie + 15s 超时）+ 统一状态码映射
    ///
    /// 与改造前的差异只有超时（20 → 15）：路径 / Cookie 头 / 解码 / 错误文案都不变；
    /// 401 清 workspace 缓存的既有语义保留在 catch 里（等价于改造前 perform 中的分支）。
    private func fetch(path: String, query: [(String, String)],
                       token: String) async throws -> Data {
        let url = try BillingHTTPMapper.url(base: baseURL, path: path, query: query)
        let endpoint = BillingEndpoint.get(url: url,
                                           headers: ["Cookie": "\(Self.sessionCookieName)=\(token)"],
                                           label: displayName,
                                           errorText: { HTTPErrorBody.message(from: $0, dialect: .plainError) },
                                           status: Self.mapHTTPError)
        do {
            return try await transport.send(endpoint)
        } catch BillingError.unauthorized {
            // 登录态失效：清掉 workspace 缓存，下次凭据更新后重新发现
            workspaceCache.clear()
            throw BillingError.unauthorized
        }
    }

    /// 状态码 → BillingError（403 的 workspace_member_required 有专门话术）
    ///
    /// 纯函数，供测试直接验证映射；`message` 是已按本家口径提取好的错误体文案。
    public static func mapHTTPError(statusCode: Int, retryAfter: TimeInterval?,
                                    message: String?) -> BillingError {
        switch statusCode {
        case 400:
            return .invalidRequest(message)
        case 401:
            return .unauthorized
        case 403:
            let text = message == "workspace_member_required"
                ? "无权访问该工作区，请确认账号仍在成员列表中"
                : message
            return .forbidden(text)
        case 429:
            return .rateLimited(retryAfter: retryAfter)
        case 500...599:
            return .serviceUnavailable(message)
        default:
            return .invalidResponse("HTTP \(statusCode)")
        }
    }

}
