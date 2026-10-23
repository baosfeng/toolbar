import Foundation

// MARK: - 计费 provider 协议

/// 计费 provider — 每个云服务商实现一份，UI 只依赖本协议
///
/// 扩展方式：新增实现类 → 在组合根 `BillingProviderRegistry.register` 注册，
/// UI 自动出现在 provider 选择器中，无需改面板代码。
public protocol BillingProvider: Sendable {
    /// 稳定标识（凭据存储键、持久化偏好都用它，发布后不可变更）
    var id: String { get }
    /// 展示名称（provider 选择器 / 标题）
    var displayName: String { get }
    /// SF Symbols 图标名（禁止 emoji）
    var symbolName: String { get }
    /// 是否返回按模型分组的明细（UI 据此决定是否显示模型 Top 列表）
    var supportsModelBreakdown: Bool { get }
    /// 是否支持时间序列（UI 据此决定是否画用时柱状图；服务端不分桶时应为 false）
    var supportsTimeSeries: Bool { get }
    /// 凭据说明（配置输入框占位文案，如「Ollama API Key」）
    var credentialHint: String { get }
    /// 凭据获取页面（配置态链接跳转目标；nil = 该 provider 无在线获取入口）
    var credentialPageURL: URL? { get }
    /// 环境变量键名（只读回退凭据；默认 `BILLING_<ID>_API_KEY`）
    var environmentCredentialKey: String { get }

    /// 查询余额与套餐额度
    func fetchBalance(credential: String) async throws -> BillingBalance

    /// 查询指定时间范围的用量
    func fetchUsage(range: BillingRange, credential: String) async throws -> BillingUsage
}

/// 计费查询错误 — 按 provider 无关语义归类，UI 直接展示 `userMessage`
public enum BillingError: Error, Sendable, Equatable {
    /// 未配置凭据
    case missingCredential
    /// 凭据无效（HTTP 401）
    case unauthorized
    /// 无权限（HTTP 403，如团队范围非管理员）
    case forbidden(String?)
    /// 请求过于频繁（HTTP 429）
    case rateLimited(retryAfter: TimeInterval?)
    /// 服务端暂不可用（HTTP 5xx）
    case serviceUnavailable(String?)
    /// 请求参数错误（HTTP 400）
    case invalidRequest(String?)
    /// 响应内容无法解析
    case invalidResponse(String)
    /// 网络层失败（连接失败 / 超时）
    case transport(String)

    /// 面向用户的中文提示
    public var userMessage: String {
        switch self {
        case .missingCredential:
            return "未配置凭据"
        case .unauthorized:
            return "凭据无效或已过期，请重新填写"
        case .forbidden(let message):
            return message ?? "无权访问该账户数据"
        case .rateLimited:
            return "查询过于频繁，请稍后重试"
        case .serviceUnavailable(let message):
            return message ?? "服务暂时不可用"
        case .invalidRequest(let message):
            return message ?? "查询参数有误"
        case .invalidResponse(let detail):
            return "响应解析失败：\(detail)"
        case .transport(let detail):
            return "网络错误：\(detail)"
        }
    }
}

// MARK: - provider 注册表

/// 计费 provider 注册表 — 组合根装配后注入 UI，未来加 provider 只需注册
///
/// 线程安全：provider 列表在启动阶段注册完成后只读；`providers` 用锁保护写入。
public final class BillingProviderRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var providers: [any BillingProvider] = []

    /// 空注册表（测试 / 未装配场景）
    public init() {}

    /// 以初始 provider 列表创建
    public init(providers: [any BillingProvider]) {
        self.providers = providers
    }

    /// 注册 provider（同 id 覆盖旧实现，便于未来替换）
    public func register(_ provider: any BillingProvider) {
        lock.lock()
        defer { lock.unlock() }
        providers.removeAll { $0.id == provider.id }
        providers.append(provider)
    }

    /// 全部 provider（注册顺序）
    public var all: [any BillingProvider] {
        lock.lock()
        defer { lock.unlock() }
        return providers
    }

    /// 按 id 查 provider
    public func provider(id: String) -> (any BillingProvider)? {
        all.first { $0.id == id }
    }

    /// 是否为空（UI 空态判断）
    public var isEmpty: Bool { all.isEmpty }
}

// MARK: - 协议默认实现

extension BillingProvider {
    /// 默认提供时间序列（provider 未声明时按支持处理）
    public var supportsTimeSeries: Bool { true }

    /// 默认无凭据获取页面
    public var credentialPageURL: URL? { nil }

    /// 默认环境变量键名
    public var environmentCredentialKey: String {
        "BILLING_\(id.uppercased())_API_KEY"
    }
}
