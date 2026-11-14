import Foundation
import NetworkMonitorCore

// MARK: - 老配置零迁移（多实例改造的关键约束）

/// 「默认实例 id == kindID」让旧版本的凭据键 / 启用键 / 环境变量键 / 提醒键原样命中。
///
/// 这条约束是升级安全性的根基：任何一处键名改动都会让老用户升级后额度页整页空态，
/// 因此这里逐键断言，而不是只测「能读出来」。
func runBillingInstanceMigrationTests() {
    print("\n🧪 Testing 老配置零迁移（默认实例仍用旧键）...")
    testLegacyCredentialZeroMigration()
    print("✅ Billing 多实例零迁移 works")
}

private func testLegacyCredentialZeroMigration() {
    let legacyID = "ollama"
    let defaultInstance = BillingInstanceID.defaultInstance(kindID: legacyID, title: "Ollama")

    assertEqual(PreferencesBillingCredentialStore.storageKey(for: defaultInstance.id),
                PreferencesBillingCredentialStore.storageKey(for: legacyID),
                "默认实例凭据键与旧版本一致（billing.credential.<kindID>）")
    assertEqual(BillingProviderPreferences.storageKey(for: defaultInstance.id),
                "billing.enabled.ollama", "默认实例启用键与旧版本一致")
    assertEqual(BillingInstanceID.environmentKey(kindID: legacyID, slug: nil),
                PreferencesBillingCredentialStore.defaultEnvironmentKey(for: legacyID),
                "默认实例环境变量键与旧版本一致")
    assertEqual(BillingProviderPreferences(storage: InMemoryStorage()).isEnabled(defaultInstance.id), true,
                "未写过启用键时默认启用（与旧版本一致）")

    let secrets = InMemorySecretStorage()
    let store = PreferencesBillingCredentialStore(storage: InMemoryStorage(), secrets: secrets,
                                                  environment: [:])
    store.setCredential("sk-legacy-value", for: legacyID)
    assertEqual(store.credential(for: defaultInstance.id) ?? "", "sk-legacy-value",
                "旧凭据键写入后，默认实例仍能读出（不改存储、不额外请求）")
    assertEqual(secrets.secret(forKey: PreferencesBillingCredentialStore.storageKey(for: defaultInstance.id)),
                "sk-legacy-value", "读出的就是密文存储里的那条，键没变")

    let workInstance = BillingInstanceID.namedInstance(kindID: legacyID, slug: "work", title: "Ollama 工作")!
    store.setCredential("sk-work-value", for: workInstance.id)
    assertEqual(store.credential(for: workInstance.id) ?? "", "sk-work-value", "命名实例有自己的凭据")
    assertEqual(store.credential(for: defaultInstance.id) ?? "", "sk-legacy-value",
                "命名实例写入不影响默认实例")

    let reset = Date(timeIntervalSince1970: 1_800_000_000)
    let balance = BillingBalance(percentLimits: [
        BillingPercentLimit(id: "session", title: "会话", remainingFraction: 0.03, resetsAt: reset),
    ])
    let result = BillingAlertEvaluator.evaluate(balance: balance, providerID: defaultInstance.id, state: [:])
    assertEqual(result.alerts.first?.key ?? "", "ollama.session", "默认实例提醒键与旧版本一致")
    assertEqual(result.alerts.first?.providerID ?? "", "ollama", "提醒里的 providerID 仍是旧标识")
}
