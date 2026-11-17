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

    /// 环境变量键的解析顺序（instance → provider 原生名 → 通用规则）
    ///
    /// 为什么不能再「一律按实例 id 推导」：provider 自己声明的厂商原生变量名
    /// （如 DeepSeek 的 `DEEPSEEK_API_KEY`、Ollama 的 `OLLAMA_API_KEY`）此前永远读不到——
    /// 装饰器把键名整个改写成了 `BILLING_<ID>_API_KEY`，provider 的声明形同注释。
    ///
    /// 现行规则（严格向后兼容，默认实例的老键仍然命中）：
    /// 1. 默认实例（id == kindID）且 provider 显式声明了键 → **用它**（回落到原实现声明的厂商名）；
    /// 2. 命名实例 → provider 键追加实例后缀（`DEEPSEEK_API_KEY` → `DEEPSEEK_WORK_API_KEY`），
    ///    保证同一 provider 的多个实例能各自 `export`；
    /// 3. 上述键都没有时，按通用规则 `BILLING_<ID>_API_KEY`。
    ///
    /// 「provider 显式声明」的判据是「与协议默认值不同」：协议默认实现本身就是
    /// `BILLING_<PROVIDER.ID>_API_KEY`，用它当哨兵即可，无需给协议加新成员。
    public var environmentCredentialKey: String {
        BillingInstanceID.resolvedEnvironmentKey(
            providerID: base.id,
            providerKey: base.environmentCredentialKey,
            instanceID: instance.id,
            instanceKey: BillingInstanceID.environmentKey(kindID: instance.kindID, slug: instance.slug),
            isDefaultInstance: instance.isDefault)
    }

    public func fetchBalance(credential: String) async throws -> BillingBalance {
        try await base.fetchBalance(credential: credential)
    }

    public func fetchUsage(range: BillingRange, credential: String) async throws -> BillingUsage {
        try await base.fetchUsage(range: range, credential: credential)
    }
}
