import Foundation

// MARK: - 静态清单检查器

/// 静态清单检查器 —— 读 releases/latest/download/update.json
///
/// 这是首选通道：一条固定 URL、走 CDN、不计 API 额度，一次请求拿到版本 + 下载地址 + 校验和。
/// 请求失败（旧发布还没上传清单 / 网络异常 / 被墙）时由 UpdateCheckerChain 回退到
/// GitHub API，于是「新发布省额度、老发布不至于查不了」。
public final class StaticManifestUpdateChecker: UpdateChecking {

    /// 默认站点的根（测试注入本地回环地址模拟失败路径）
    public static let defaultBaseURL = URL(string: "https://github.com")!
    /// 默认仓库（owner/repo）
    public static let defaultRepository = "baosfeng/toolbar"
    /// 请求超时（秒）：清单很小，8 秒足够；启动后自动检查不能挂太久
    public static let defaultTimeout: TimeInterval = 8

    private let baseURL: URL
    private let repository: String
    private let userAgent: String
    private let timeout: TimeInterval
    private let transport: any HTTPTransport

    /// - Parameters:
    ///   - userAgent: 形如「一览/1.30.0」，由 App 层拼好传入（Core 不知道自身版本）
    ///   - transport: 出网实现（缺省用共享实例，供测试注入替身）
    public init(baseURL: URL = StaticManifestUpdateChecker.defaultBaseURL,
                repository: String = StaticManifestUpdateChecker.defaultRepository,
                userAgent: String,
                timeout: TimeInterval = StaticManifestUpdateChecker.defaultTimeout,
                transport: any HTTPTransport = URLSessionHTTPTransport.shared) {
        self.baseURL = baseURL
        self.repository = repository
        self.userAgent = userAgent
        self.timeout = timeout
        self.transport = transport
    }

    public func fetchLatestRelease() async throws -> UpdateRelease {
        let endpoint = Endpoint<Data>(method: .get,
                                      url: try manifestURL(),
                                      headers: ["Accept": "application/json"],
                                      userAgent: userAgent,
                                      timeout: timeout,
                                      // 清单必须拿最新的：命中缓存会看到已经修过的旧版本号
                                      cachePolicy: .reloadIgnoringLocalCacheData,
                                      label: "更新清单",
                                      decoder: { $0 },
                                      // 与 API 通道同一套失败口径（超时 / 网络 / 限流），界面文案不用分叉
                                      errorMapper: GitHubUpdateChecker.mapFailure)
        let data = try await transport.send(endpoint)
        return try UpdateManifestParser.release(fromJSON: data)
    }

    /// - Note: typed throws（SE-0413）：拼不出 URL 只有一种失败
    private func manifestURL() throws(UpdateCheckError) -> URL {
        let root = baseURL.absoluteString.hasSuffix("/")
            ? String(baseURL.absoluteString.dropLast())
            : baseURL.absoluteString
        guard let url = URL(string: root + "/" + repository + "/releases/latest/download/update.json") else {
            throw UpdateCheckError.invalidResponse("无效的请求地址")
        }
        return url
    }
}

// MARK: - 通道链

/// 检查通道链 —— 主通道（静态清单）失败就用备用通道（GitHub API）
///
/// 为什么保留 API：1.29 及更早的发布没有 update.json 资产，
/// 用户从 1.29 升到 1.30 这一跳必须还能查到版本，否则「升级一次才能用上新通道」就成了死锁。
/// 1.31 之后如果确认所有在跑的版本都能读清单，这条备用通道可以删掉。
public struct UpdateCheckerChain: UpdateChecking {

    private let primary: any UpdateChecking
    private let fallback: any UpdateChecking
    private let logger: LoggingService

    public init(primary: any UpdateChecking,
                fallback: any UpdateChecking,
                logger: LoggingService = AppContext.shared.logger) {
        self.primary = primary
        self.fallback = fallback
        self.logger = logger
    }

    public func fetchLatestRelease() async throws -> UpdateRelease {
        do {
            return try await primary.fetchLatestRelease()
        } catch {
            let reason = (error as? UpdateCheckError)?.userMessage ?? error.localizedDescription
            // 主通道失败不是错误级别：老发布本来就没有清单资产，属于预期路径
            logger.info("更新检查：静态清单不可用（\(reason)），回退 GitHub API")
        }
        return try await fallback.fetchLatestRelease()
    }
}
