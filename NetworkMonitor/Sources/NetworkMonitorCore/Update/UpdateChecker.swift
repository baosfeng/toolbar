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
    /// 附件清单（旧发布的安装包 zip；按架构各一个）
    public let assets: [UpdateAsset]
    /// 静态清单给出的唯一安装包（universal dmg）
    ///
    /// 新发布都走清单通道，这里必有值；为 nil 只可能来自「旧发布回退 API」，
    /// 那时按本机架构从 assets 里挑 zip（兼容 1.29 及更早的发布）。
    public let artifact: UpdateArtifact?

    public init(tagName: String, htmlURL: URL?, notes: String, publishedAt: Date?,
                assets: [UpdateAsset] = [], artifact: UpdateArtifact? = nil) {
        self.tagName = tagName
        self.htmlURL = htmlURL
        self.notes = notes
        self.publishedAt = publishedAt
        self.assets = assets
        self.artifact = artifact
    }

    /// 资产名清单（选择本机架构包 / 报错文案用）
    public var assetNames: [String] { assets.map(\.name) }
}

// MARK: - 发布附件

/// 发布附件 —— releases API 里的 `assets`（只留安装包要用的两列）
///
/// 名字与下载地址是分开的两件事：资产名决定「选哪个架构」，
/// 地址可以是 `browser_download_url` 或镜像地址，所以两者都留。
public struct UpdateAsset: Equatable, Sendable {
    /// 资产名（Yilan-1.30.0.dmg / 旧发布的 Yilan-arm64.app.zip）
    public let name: String
    /// 下载地址（缺地址时视为不可用）
    public let downloadURL: URL?
    /// GitHub 给出的内容校验和（形如 `sha256:<hex>`；早期资产没有这一列）
    ///
    /// 有了它，API 回退路径（清单不可用时）也能做完整性校验，
    /// 不用退化成「只验包内版本号」。
    public let digest: String?

    public init(name: String, downloadURL: URL?, digest: String? = nil) {
        self.name = name
        self.downloadURL = downloadURL
        self.digest = digest
    }

    /// 归一化后的 SHA-256（只认 sha256 摘要；其它算法 / 缺失 → nil）
    public var sha256: String? {
        guard let digest, digest.lowercased().hasPrefix("sha256:") else { return nil }
        let hex = String(digest.dropFirst("sha256:".count))
        return hex.isEmpty ? nil : hex.lowercased()
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
    /// 统一传输层（由组合根按协议注入）
    private let transport: any HTTPTransport

    /// - Parameters:
    ///   - userAgent: 形如「一览/1.24.2」，由 App 层拼好传入（Core 不知道自身版本）
    ///   - transport: 出网实现（缺省用共享实例，供测试注入替身）
    ///   - logger: 保留签名兼容；出网日志由 transport 输出
    public init(baseURL: URL = GitHubUpdateChecker.defaultBaseURL,
                repository: String = GitHubUpdateChecker.defaultRepository,
                userAgent: String,
                timeout: TimeInterval = GitHubUpdateChecker.defaultTimeout,
                transport: any HTTPTransport = URLSessionHTTPTransport.shared,
                logger: LoggingService = AppContext.shared.logger) {
        self.baseURL = baseURL
        self.repository = repository
        self.userAgent = userAgent
        self.timeout = timeout
        self.transport = transport
    }

    // MARK: 请求

    /// 一次请求：统一 Endpoint（GitHub 头 + 8s 超时 + 不吃缓存），错误仍收成 UpdateCheckError
    public func fetchLatestRelease() async throws -> UpdateRelease {
        let endpoint = Endpoint<Data>(method: .get,
                                      url: try makeURL(),
                                      headers: ["Accept": "application/vnd.github+json",
                                                "X-GitHub-Api-Version": "2022-11-28"],
                                      userAgent: userAgent,
                                      // GitHub 给 API 响应带 max-age=60：命中缓存时「检查更新」
                                      // 会拿到一分钟内的旧结果（发布新版本后立刻再查一次就看不出来）
                                      timeout: timeout,
                                      cachePolicy: .reloadIgnoringLocalCacheData,
                                      label: "更新检查",
                                      decoder: { $0 },
                                      errorMapper: Self.mapFailure)
        let data = try await transport.send(endpoint)
        return try Self.release(fromJSON: data)
    }

    /// - Note: typed throws（SE-0413）：拼不出 URL 只有一种失败，错误域封闭。
    private func makeURL() throws(UpdateCheckError) -> URL {
        let root = baseURL.absoluteString.hasSuffix("/")
            ? String(baseURL.absoluteString.dropLast())
            : baseURL.absoluteString
        guard let url = URL(string: root + "/repos/" + repository + "/releases/latest") else {
            throw UpdateCheckError.invalidResponse("无效的请求地址")
        }
        return url
    }

    // MARK: 映射

    /// 传输层失败 → UpdateCheckError（错误仍由本家定义，传输层不感知）
    ///
    /// public 供 TestRunner 直接断言（与 release(fromJSON:) 同一处理口径）。
    public static func mapFailure(_ failure: HTTPFailure) -> UpdateCheckError {
        switch failure {
        case .transport(let detail):
            // 超时单独成一类，其余都归「网络不可用」（与改造前 mapTransport 同口径）
            return detail.isTimeout ? .timedOut : .noNetwork
        case .notHTTP:
            return .invalidResponse("非 HTTP 响应")
        case .response(let response):
            return mapStatus(statusCode: response.statusCode,
                             rateLimitRemaining: response.header("x-ratelimit-remaining"),
                             data: response.data)
        }
    }

    /// HTTP 状态归一化（限流优先于通用 403：GitHub 限额用尽也是 403）
    public static func mapStatus(statusCode: Int, rateLimitRemaining: String?, data: Data) -> UpdateCheckError {
        let message = detailMessage(from: data)
        if statusCode == 429 { return .rateLimited }
        if statusCode == 403 {
            if rateLimitRemaining == "0" || message.lowercased().contains("rate limit") {
                return .rateLimited
            }
        }
        return .httpStatus(statusCode, message)
    }

    static func detailMessage(from data: Data) -> String {
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
        let assets: [AssetPayload]?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case body
            case publishedAt = "published_at"
            case assets
        }
    }

    /// 附件子集（`browser_download_url` 是 GitHub 给的真实下载地址）
    private struct AssetPayload: Decodable {
        let name: String?
        let browserDownloadURL: String?
        let digest: String?

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
            case digest
        }
    }

    /// JSON → `UpdateRelease`（供网络层与测试共用）
    ///
    /// 缺 `tag_name` 直接算解析失败：没有版本号的发布无法判定新旧，
    /// 静默返回空 tag 会让界面上「最新版本」永远空白且看不出原因。
    ///
    /// - Note: 用 typed throws（SE-0413）声明 `UpdateCheckError`：本函数的失败种类封闭
    ///   （JSON 形态不符 / 缺 tag_name 两种），解码错误已在内部就地翻成领域错误；
    ///   声明后任何新增的抛出点若不属于这个错误域，编译期即报红。
    public static func release(fromJSON data: Data) throws(UpdateCheckError) -> UpdateRelease {
        let payload: ReleasePayload
        do {
            payload = try JSONDecoder().decode(ReleasePayload.self, from: data)
        } catch {
            throw UpdateCheckError.invalidResponse("发布信息不是预期 JSON")
        }
        guard let tag = payload.tagName, !tag.isEmpty else {
            throw UpdateCheckError.invalidResponse("缺少 tag_name")
        }
        let assets = (payload.assets ?? []).compactMap { asset -> UpdateAsset? in
            guard let name = asset.name, !name.isEmpty else { return nil }
            return UpdateAsset(name: name,
                               downloadURL: asset.browserDownloadURL.flatMap { URL(string: $0) },
                               digest: asset.digest)
        }
        return UpdateRelease(tagName: tag,
                             htmlURL: payload.htmlURL.flatMap { URL(string: $0) },
                             notes: payload.body ?? "",
                             publishedAt: payload.publishedAt.flatMap { try? Date($0, strategy: .iso8601) },
                             assets: assets)
    }
}