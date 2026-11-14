import Foundation
import NetworkMonitorCore

// MARK: - 额度页可见性 + 同一实例唯一配置

/// 两条行为契约的单测：额度页只展示「已启用 + 已配置」的 provider；
/// 一个**实例**只有一条生效凭据（存储优先、环境变量仅回退）。
/// 同一 provider 类型可以有多个实例，实例之间凭据互不覆盖（见 BillingInstanceTests）。
func runBillingVisibilityTests() {
    print("\n🧪 Testing BillingVisibilityRule...")
    testBillingVisibilityRule()

    print("\n🧪 Testing 同一实例唯一配置（注册表 / 凭据）...")
    testSingleConfigurationContract()
}

// MARK: - 可见性

private func testBillingVisibilityRule() {
    assertEqual(BillingVisibilityRule.isVisibleInCredits(isConfigured: true, isEnabled: true), true,
                "已配置 + 已启用 → 出现在额度页")
    assertEqual(BillingVisibilityRule.isVisibleInCredits(isConfigured: false, isEnabled: true), false,
                "未配置 → 额度页不占位（用户要求「没有配置的需要隐藏」）")
    assertEqual(BillingVisibilityRule.isVisibleInCredits(isConfigured: true, isEnabled: false), false,
                "停用 → 不出现（与启用开关语义一致）")
    assertEqual(BillingVisibilityRule.isVisibleInCredits(isConfigured: false, isEnabled: false), false,
                "两项都不满足 → 不出现")

    let entries = [(id: "ollama", configured: true, enabled: true),
                   (id: "open-design", configured: false, enabled: true),
                   (id: "opencode-go", configured: true, enabled: false),
                   (id: "x", configured: true, enabled: true)]
    let visible = BillingVisibilityRule.visibleEntries(entries,
                                                       isConfigured: { $0.configured },
                                                       isEnabled: { $0.enabled })
    assertEqual(visible.map(\.id), ["ollama", "x"], "只保留可见项且保持输入顺序")

    assertEqual(BillingVisibilityRule.visibleEntries(entries,
                                                     isConfigured: { _ in false },
                                                     isEnabled: { _ in true }).count, 0,
                "全部未配置 → 可见集合为空（额度页走空态）")
    assertEqual(BillingVisibilityRule.isEmptyState(visibleCount: 0), true, "0 个可见即空态")
    assertEqual(BillingVisibilityRule.isEmptyState(visibleCount: 1), false, "有可见项不空态")
    // 空态判据对负数输入也是稳定的（防御：调用方不应传负数，但不得崩）
    assertEqual(BillingVisibilityRule.isEmptyState(visibleCount: -1), false,
                "负数不当成空态（防御性，不崩）")
}

// MARK: - 唯一配置

/// 三种「重复配置」入口逐一断言：注册表同实例 / 凭据双写 / 来源优先级
///
/// 多实例改造后本契约的粒度从「provider」收紧为「实例」：默认实例的标识仍等于 kindID，
/// 因此老配置的键与行为完全不变；命名实例（`cursor::work`）另有独立凭据与启用开关。
private func testSingleConfigurationContract() {
    // 1) 注册表：同 id 再次 register = 覆盖，列表里永远只有一个同 id 实例
    let registry = BillingProviderRegistry()
    registry.register(StubProvider(id: "ollama", displayName: "Ollama"))
    registry.register(StubProvider(id: "open-design", displayName: "Open Design"))
    registry.register(StubProvider(id: "ollama", displayName: "Ollama（替换）"))
    assertEqual(registry.all.count, 2, "同 id 重复注册不新增条目")
    assertEqual(registry.all.filter { $0.id == "ollama" }.count, 1, "同 id 在注册表里唯一")
    assertEqual(registry.all.map(\.id), ["open-design", "ollama"], "覆盖后移到末位并保持唯一")
    assertEqual(registry.provider(id: "ollama")?.displayName, "Ollama（替换）",
                "覆盖后生效的是新实现（契约：register 是替换不是追加）")

    // 2) 凭据：同一 provider 只有一条存储键，写入永远是覆盖
    let storage = InMemoryStorage()
    let secrets = InMemorySecretStorage()
    let store = PreferencesBillingCredentialStore(storage: storage, secrets: secrets, environment: [:])
    store.setCredential("sk-first", for: "ollama")
    store.setCredential("sk-second", for: "ollama")
    assertEqual(store.credential(for: "ollama"), "sk-second", "重复写入是替换，不留第二份")
    assertEqual(secrets.secret(forKey: PreferencesBillingCredentialStore.storageKey(for: "ollama")),
                "sk-second", "唯一存储键 billing.credential.<id> 落在秘密存储")
    assertEqual(secrets.values.count, 1, "同一 provider 在钥匙串里只有一条记录")

    // 3) 来源优先级：存储优先，环境变量仅回退，绝不出现「两个来源的配置」
    let envOnly = PreferencesBillingCredentialStore(storage: InMemoryStorage(),
                                                    secrets: InMemorySecretStorage(),
                                                    environment: ["BILLING_OLLAMA_API_KEY": "env-key"])
    let envResolution = envOnly.credentialResolution(for: "ollama")
    assertEqual(envResolution.source, .environment, "只有环境变量时来源为 environment")
    assertEqual(envResolution.credential, "env-key", "回退值即生效值")

    let mixedStorage = InMemoryStorage()
    mixedStorage.set("stored-key", forKey: PreferencesBillingCredentialStore.storageKey(for: "ollama"))
    let mixed = PreferencesBillingCredentialStore(storage: mixedStorage,
                                                  secrets: InMemorySecretStorage(),
                                                  environment: ["BILLING_OLLAMA_API_KEY": "env-key"])
    let mixedResolution = mixed.credentialResolution(for: "ollama")
    assertEqual(mixedResolution.credential, "stored-key", "两者都有时以存储为准")
    assertEqual(mixedResolution.source, .stored, "来源标记为 stored（设置页据此显示）")
    assertEqual(mixed.credential(for: "ollama"), mixedResolution.credential,
                "credential() 与 credentialResolution() 取同一个值（不会出现两套配置）")

    // 4) 未配置：来源 none，isConfigured 为 false（额度页据此隐藏）
    let empty = PreferencesBillingCredentialStore(storage: InMemoryStorage(),
                                                  secrets: InMemorySecretStorage(), environment: [:])
    assertEqual(empty.credentialResolution(for: "open-design").source, .none, "未配置来源 none")
    assertEqual(empty.credentialResolution(for: "open-design").isConfigured, false, "未配置不可见")
    assertNotNil(empty.credentialResolution(for: "open-design").storageKey, "解析结果带唯一存储键")
    assertEqual(empty.credentialResolution(for: "open-design").environmentKeys,
                ["BILLING_OPEN_DESIGN_API_KEY", "BILLING_OPEN-DESIGN_API_KEY"],
                "解析结果带参与尝试的环境变量键（默认键 + 旧连字符键，去重后 2 个）")

    // 5) 多实例：同一 provider 类型的两个实例各一条凭据，互不覆盖
    let multiSecrets = InMemorySecretStorage()
    let multi = PreferencesBillingCredentialStore(storage: InMemoryStorage(), secrets: multiSecrets,
                                                  environment: [:])
    multi.setCredential("sk-default", for: "cursor")
    multi.setCredential("sk-work", for: "cursor::work")
    assertEqual(multi.credential(for: "cursor") ?? "", "sk-default", "默认实例凭据不被命名实例覆盖")
    assertEqual(multi.credential(for: "cursor::work") ?? "", "sk-work", "命名实例有独立凭据")
    assertEqual(multiSecrets.values.count, 2, "两个实例在秘密存储里是两条记录")
}

// MARK: - 桩 provider

/// 测试用 provider 桩（只实现协议必需成员）
private struct StubProvider: BillingProvider {
    let id: String
    let displayName: String
    var symbolName: String { "circle" }
    var supportsModelBreakdown: Bool { true }
    var credentialHint: String { "Stub Key" }

    func fetchBalance(credential: String) async throws -> BillingBalance { BillingBalance() }

    func fetchUsage(range: BillingRange, credential: String) async throws -> BillingUsage {
        BillingUsage(range: range, granularity: .day, start: Date(), end: Date(),
                     totals: BillingMetrics(), buckets: [])
    }
}
