import Foundation

// MARK: - 实例化 provider 装饰器

/// 把「provider 类型 + 实例」合成为一份 provider —— `id` 直接就是实例标识
///
/// 这样做的收益：状态管理器（`BillingMonitor`）的状态表 / 代次表 / 节流表、
/// 凭据存储键、提醒状态键全部沿用现有实现，**多实例不需要改状态机**；
/// 现有 provider 实现（Ollama / Open Design / OpenCode Go / Cursor / Codex / Claude）
/// 也无需感知实例概念，各自仍按「一份凭据查一份额度」工作。
public struct BillingProviderInstance: BillingProvider {
    /// 原实现（其 `id` 是 provider 类型标识 kindID）
    public let base: any BillingProvider
    /// 实例信息（`id` 是实例标识）
    public let instance: BillingInstance

    public init(base: any BillingProvider, instance: BillingInstance) {
        self.base = base
        self.instance = instance
    }

    // MARK: - BillingProvider

    /// 实例标识（凭据 / 启用 / 提醒键都用它）
    public var id: String { instance.id }

    /// 实例展示名
    public var displayName: String { instance.title }

    /// 以下能力位与凭据说明全部转发原实现
    public var symbolName: String { base.symbolName }
    public var supportsModelBreakdown: Bool { base.supportsModelBreakdown }
    public var supportsTimeSeries: Bool { base.supportsTimeSeries }
    public var supportsUsage: Bool { base.supportsUsage }
    public var supportedUsageRanges: [BillingRange] { base.supportedUsageRanges }
    public var minimumRefreshInterval: TimeInterval { base.minimumRefreshInterval }
    public var credentialHint: String { base.credentialHint }
    public var credentialPageURL: URL? { base.credentialPageURL }

    /// 环境变量键按实例区分：默认实例与旧版本完全一致，命名实例追加后缀
    public var environmentCredentialKey: String {
        BillingInstanceID.environmentKey(kindID: instance.kindID, slug: instance.slug)
    }

    public func fetchBalance(credential: String) async throws -> BillingBalance {
        try await base.fetchBalance(credential: credential)
    }

    public func fetchUsage(range: BillingRange, credential: String) async throws -> BillingUsage {
        try await base.fetchUsage(range: range, credential: credential)
    }
}
