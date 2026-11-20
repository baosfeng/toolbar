import Foundation

// MARK: - 安装错误

/// 安装失败 —— 每一种都发生在「当前应用包未被替换」的前提下
///
/// 安装是 fail-closed 的：下载 / 解压 / 校验 / 备份任一步失败都只回报原因，
/// 不动目标 .app；只有「备份成功且新包已就位」才轮到替换。
public enum UpdateInstallError: Error, Equatable, Sendable {
    /// 发布里没有本机架构的资产（expected 是本机需要的资产名）
    case assetMissing(expected: String, available: [String])
    /// 资产没有下载地址
    case assetUnavailable(String)
    /// 下载失败（网络 / 非 2xx）
    case downloadFailed(String)
    /// 解压失败（zip 损坏 / 结构不对）
    case unpackFailed(String)
    /// 解压后找不到 .app
    case appNotFound(String)
    /// 版本对不上（远端 tag 与包内 CFBundleShortVersionString 不一致）
    case versionMismatch(expected: String, actual: String)
    /// 目标路径不是当前正在运行的应用包（拒绝盲删）
    case targetMismatch(String)
    /// 目标目录不可写（/Applications 需要管理员权限等）
    case targetNotWritable(String)
    /// 备份当前包失败
    case backupFailed(String)
    /// 替换失败（已回滚到原版本）
    case replaceFailed(String)
    /// 重启失败（包已替换，需用户手动启动）
    case relaunchFailed(String)

    /// 面向用户的中文原因（界面「安装失败（…）」里那一段）
    public var userMessage: String {
        switch self {
        case .assetMissing(let expected, let available):
            let names = available.isEmpty ? "无资产" : available.joined(separator: " / ")
            return "发布里没有 \(expected)（现有：\(names)）"
        case .assetUnavailable(let name):
            return "\(name) 没有下载地址"
        case .downloadFailed(let detail):
            return detail.isEmpty ? "下载失败" : "下载失败（\(detail)）"
        case .unpackFailed(let detail):
            return detail.isEmpty ? "解压失败" : "解压失败（\(detail)）"
        case .appNotFound(let detail):
            return detail.isEmpty ? "安装包里没有应用" : "安装包里没有应用（\(detail)）"
        case .versionMismatch(let expected, let actual):
            return "版本不符（期望 \(expected)，实际 \(actual)）"
        case .targetMismatch(let detail):
            return "目标不是当前运行的应用（\(detail)）"
        case .targetNotWritable(let detail):
            return "没有写入权限（\(detail)）"
        case .backupFailed(let detail):
            return "备份当前版本失败（\(detail)）"
        case .replaceFailed(let detail):
            return "替换失败，已恢复原版本（\(detail)）"
        case .relaunchFailed(let detail):
            return "已安装但重启失败（\(detail)），请手动启动"
        }
    }
}

// MARK: - 下载

/// 安装包下载 —— 安装器只依赖本协议
///
/// 实现走统一 HTTP 传输层（Endpoint 声明地址与超时），不另起 URLSession；
/// 测试注入假实现即可在不起网络的情况下走完整个安装流程。
public protocol UpdatePackageDownloading: Sendable {
    /// 下载一个安装包（返回原始字节）
    func downloadPackage(from url: URL) async throws -> Data
}

/// 基于统一传输层的下载实现
public final class UpdatePackageDownloader: UpdatePackageDownloading {

    /// 默认超时（安装包比 JSON 大一个量级，给 60 秒）
    public static let defaultTimeout: TimeInterval = 60

    private let userAgent: String
    private let timeout: TimeInterval
    private let transport: any HTTPTransport

    /// - Parameters:
    ///   - transport: 出网实现（缺省用共享实例，供测试注入替身）
    ///   - logger: 保留签名兼容；出网日志由 transport 输出
    public init(userAgent: String,
                timeout: TimeInterval = UpdatePackageDownloader.defaultTimeout,
                transport: any HTTPTransport = URLSessionHTTPTransport.shared,
                logger: LoggingService = AppContext.shared.logger) {
        self.userAgent = userAgent
        self.timeout = timeout
        self.transport = transport
    }

    public func downloadPackage(from url: URL) async throws -> Data {
        let endpoint = Endpoint<Data>(method: .get,
                                      url: url,
                                      headers: ["Accept": "application/octet-stream"],
                                      userAgent: userAgent,
                                      timeout: timeout,
                                      // 安装包必须拿最新的：命中缓存等于装回旧包
                                      cachePolicy: .reloadIgnoringLocalCacheData,
                                      label: "安装包下载",
                                      decoder: { $0 },
                                      errorMapper: Self.mapFailure)
        return try await transport.send(endpoint)
    }

    /// 传输失败 → 安装错误（与检查失败同一套中文口径）
    public static func mapFailure(_ failure: HTTPFailure) -> UpdateInstallError {
        switch failure {
        case .transport(let detail):
            return .downloadFailed(detail.isTimeout ? "请求超时" : detail.message)
        case .notHTTP:
            return .downloadFailed("非 HTTP 响应")
        case .response(let response):
            return .downloadFailed("HTTP \(response.statusCode)")
        }
    }
}

// MARK: - 重启

/// 重启 —— 替换完成后打开新包并退出当前进程
public protocol UpdateRelaunching: Sendable {
    /// 打开指定 .app（真实实现走 /usr/bin/open -n）
    func relaunch(appURL: URL) throws
}

/// 真实实现：open -n <app> 起一个新实例
public struct WorkspaceUpdateRelauncher: UpdateRelaunching {

    public init() {}

    public func relaunch(appURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        // -n：新开一个实例，避免 LaunchServices 认为「已经在跑」而复用旧进程
        process.arguments = ["-n", appURL.path]
        do {
            try process.run()
        } catch {
            throw UpdateInstallError.relaunchFailed(error.localizedDescription)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateInstallError.relaunchFailed("open 退出码 \(process.terminationStatus)")
        }
    }
}

// MARK: - 包版本校验

/// 读包内版本号 —— 校验「装上的就是提示的那个版本」
public protocol UpdateBundleProbing: Sendable {
    /// 读 .app 的 CFBundleShortVersionString（读不出 → nil）
    func shortVersion(atAppURL url: URL) -> String?
}

/// 真实实现：用 Bundle(url:) 读 Info.plist
public struct BundleUpdateBundleProbe: UpdateBundleProbing {

    public init() {}

    public func shortVersion(atAppURL url: URL) -> String? {
        Bundle(url: url)?.infoDictionary?["CFBundleShortVersionString"] as? String
    }
}

/// 安装包校验实现 —— 版本号语义在 UI 库（`UpdateVersionLogic`），由 App 层注入解析闭包
///
/// 为什么把解析器做成闭包参数：Core 不能依赖 NetworkMonitorUI（依赖方向硬约束），
/// 而「tag 怎么解析成版本号」必须与检查更新用同一份口径，不能各写一套。
public struct UpdatePackageVerifier: UpdatePackageVerifying {

    private let probe: any UpdateBundleProbing
    private let versionFromTag: @Sendable (String) -> String?

    public init(probe: any UpdateBundleProbing = BundleUpdateBundleProbe(),
                versionFromTag: @escaping @Sendable (String) -> String?) {
        self.probe = probe
        self.versionFromTag = versionFromTag
    }

    public func verify(appURL: URL, tag: String) throws -> String {
        guard let actual = probe.shortVersion(atAppURL: appURL) else {
            throw UpdateInstallError.appNotFound("读不出包内版本号")
        }
        guard let expected = versionFromTag(tag) else {
            throw UpdateInstallError.versionMismatch(expected: tag, actual: actual)
        }
        guard actual.trimmingCharacters(in: .whitespaces) == expected else {
            throw UpdateInstallError.versionMismatch(expected: expected, actual: actual)
        }
        return actual
    }
}
