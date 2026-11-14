import Foundation

// MARK: - 发布信息

/// 远端发布 — 只保留界面要用的四个字段
///
/// 版本号本身不在这里解析：解析与比较属于展示口径（`NetworkMonitorUI.UpdateVersionLogic`），
/// Core 只负责「把 JSON 变成值」，不决定 tag 怎么解释。
public struct UpdateRelease: Equatable, Sendable {
    /// 原始 tag（`v1.24.10`）
    public let tagName: String
    /// 发布页（「打开发布页」按钮的目标）
    public let htmlURL: URL?
    /// 发布说明正文（未截断）
    public let notes: String
    /// 发布时间（解析失败为 nil，不阻塞版本判定）
    public let publishedAt: Date?

    public init(tagName: String, htmlURL: URL?, notes: String, publishedAt: Date?) {
        self.tagName = tagName
        self.htmlURL = htmlURL
        self.notes = notes
        self.publishedAt = publishedAt
    }
}

// MARK: - 检查协议

/// 更新检查 — UI 只依赖本协议
///
/// 协议化是为了两件事：测试注入假实现（不联网也能断言五种状态），
/// 以及后续换数据源（例如镜像接口）时不动界面与服务层。
public protocol UpdateChecking: Sendable {
    /// 查询最新发布
    func fetchLatestRelease() async throws -> UpdateRelease
}

// MARK: - 检查错误

/// 更新检查错误 — 每种失败都映射成一句用户能看懂的原因
///
/// 匿名只读接口的失败只有这几类，界面统一显示「无法检查（原因）」，
/// 不弹窗、不重试轰炸（重试由用户点按钮触发）。
public enum UpdateCheckError: Error, Equatable, Sendable {
    /// 无网络 / 域名不可达 / 连接被拒
    case noNetwork
    /// 请求超时（URLSession 按 8 秒超时）
    case timedOut
    /// GitHub 限流（HTTP 403 且剩余配额为 0，或 HTTP 429）
    case rateLimited
    /// 其它非 2xx 状态
    case httpStatus(Int, String)
    /// 响应不是预期 JSON / 缺关键字段
    case invalidResponse(String)

    /// 面向用户的中文原因（塞进「无法检查（…）」）
    public var userMessage: String {
        switch self {
        case .noNetwork:
            return "网络不可用"
        case .timedOut:
            return "请求超时"
        case .rateLimited:
            return "GitHub 限流，请稍后重试"
        case .httpStatus(let code, let detail):
            return detail.isEmpty ? "服务返回 HTTP \(code)" : "服务返回 HTTP \(code)：\(detail)"
        case .invalidResponse(let detail):
            return "响应解析失败（\(detail)）"
        }
    }
}

// MARK: - GitHub Releases 实现

/// GitHub Releases 检查器 — `GET /repos/{owner}/{repo}/releases/latest`
///
/// 口径：
/// - 匿名请求：不带 Authorization，不带任何用户标识，UA 只有「应用名/版本」；
/// - 超时 8 秒（启动后自动检查，不能让半分钟的等待挂在设置页上）；
/// - `Accept: application/vnd.github+json` + 固定 API 版本头，响应形状稳定；
/// - 只读不下载：本应用自签名，自动替换 .app 会让 TCC 授权（屏幕录制 / 辅助功能）全部失效，
///   所以这里到「告诉用户有新版」为止，安装由用户自己点发布页完成。
public final class GitHubUpdateChecker: UpdateChecking {

    /// 默认 API 根地址（测试注入本地回环地址模拟失败路径）
    public static let defaultBaseURL = URL(string: "https://api.github.com")!
    /// 默认仓库（`owner/repo`）
    public static let defaultRepository = "baosfeng/toolbar"
    /// 请求超时（秒）
    public static let defaultTimeout: TimeInterval = 8

    private let baseURL: URL
    private let repository: String
    private let userAgent: String
    private let timeout: TimeInterval
    private let session: URLSession
    private let logger: LoggingService

    /// - Parameters:
    ///   - userAgent: 形如「一览/1.24.2」，由 App 层拼好传入（Core 不知道自身版本）
    public init(baseURL: URL = GitHubUpdateChecker.defaultBaseURL,
                repository: String = GitHubUpdateChecker.defaultRepository,
                userAgent: String,
                timeout: TimeInterval = GitHubUpdateChecker.defaultTimeout,
                session: URLSession = .shared,
                logger: LoggingService = AppContext.shared.logger) {
        self.baseURL = baseURL
        self.repository = repository
        self.userAgent = userAgent
        self.timeout = timeout
        self.session = session
        self.logger = logger
    }

    // MARK: 请求

    public func fetchLatestRelease() async throws -> UpdateRelease {
        let request = try makeRequest()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            let mapped = Self.mapTransport(error)
            logger.warning("更新检查失败：URLError(\(error.code.rawValue)) \(error.localizedDescription)")
            throw mapped
        } catch {
            logger.warning("更新检查失败：\(error.localizedDescription)")
            throw UpdateCheckError.noNetwork
        }
        guard let http = response as? HTTPURLResponse else {
            throw UpdateCheckError.invalidResponse("非 HTTP 响应")
        }
        guard (200..<300).contains(http.statusCode) else {
            let mapped = Self.mapStatus(http, data: data)
            logger.warning("更新检查失败：HTTP \(http.statusCode) → \(mapped.userMessage)")
            throw mapped
        }
        return try Self.release(fromJSON: data)
    }

    private func makeRequest() throws -> URLRequest {
        let root = baseURL.absoluteString.hasSuffix("/")
            ? String(baseURL.absoluteString.dropLast())
            : baseURL.absoluteString
        guard let url = URL(string: root + "/repos/" + repository + "/releases/latest") else {
            throw UpdateCheckError.invalidResponse("无效的请求地址")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        // 不吃 HTTP 缓存：GitHub 给 API 响应带 max-age=60，命中缓存时「检查更新」
        // 会拿到一分钟内的旧结果（发布新版本后立刻再查一次就看不出来）
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    // MARK: 映射

    /// 网络层错误归一化（超时单独成一类，其余都归「网络不可用」）
    static func mapTransport(_ error: URLError) -> UpdateCheckError {
        switch error.code {
        case .timedOut:
            return .timedOut
        case .cancelled:
            return .noNetwork
        default:
            return .noNetwork
        }
    }

    /// HTTP 状态归一化（限流优先于通用 403：GitHub 限额用尽也是 403）
    static func mapStatus(_ http: HTTPURLResponse, data: Data) -> UpdateCheckError {
        let message = detailMessage(from: data)
        if http.statusCode == 429 { return .rateLimited }
        if http.statusCode == 403 {
            let remaining = http.value(forHTTPHeaderField: "X-RateLimit-Remaining")
            if remaining == "0" || message.lowercased().contains("rate limit") {
                return .rateLimited
            }
        }
        return .httpStatus(http.statusCode, message)
    }

    private static func detailMessage(from data: Data) -> String {
        struct Payload: Decodable { let message: String? }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              let message = payload.message, !message.isEmpty else { return "" }
        // GitHub 的报错是英文长句：截到 60 字，界面一行放得下
        return message.count > 60 ? String(message.prefix(60)) + "…" : message
    }

    // MARK: 解码

    /// Releases API 的响应子集
    private struct ReleasePayload: Decodable {
        let tagName: String?
        let htmlURL: String?
        let body: String?
        let publishedAt: String?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case body
            case publishedAt = "published_at"
        }
    }

    /// JSON → `UpdateRelease`（供网络层与测试共用）
    ///
    /// 缺 `tag_name` 直接算解析失败：没有版本号的发布无法判定新旧，
    /// 静默返回空 tag 会让界面上「最新版本」永远空白且看不出原因。
    public static func release(fromJSON data: Data) throws -> UpdateRelease {
        let payload: ReleasePayload
        do {
            payload = try JSONDecoder().decode(ReleasePayload.self, from: data)
        } catch {
            throw UpdateCheckError.invalidResponse("发布信息不是预期 JSON")
        }
        guard let tag = payload.tagName, !tag.isEmpty else {
            throw UpdateCheckError.invalidResponse("缺少 tag_name")
        }
        return UpdateRelease(tagName: tag,
                             htmlURL: payload.htmlURL.flatMap { URL(string: $0) },
                             notes: payload.body ?? "",
                             publishedAt: payload.publishedAt.flatMap { try? Date($0, strategy: .iso8601) })
    }
}
