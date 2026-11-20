import Foundation
import NetworkMonitorCore
import NetworkMonitorFeatureBilling

// MARK: - 额度服务层（独立 target）边界测试

/// 跨 target 断言：额度快照的可见性过滤住在新拆出的 `NetworkMonitorFeatureBilling` 里，
/// TestRunner 直接 import 该模块、走真实入口（`makeState` → `Snapshot.make`）。
///
/// 改造前这条测不到：服务层在可执行 target `NetworkMonitor` 里够不着，测试只能断言
/// Core 的判据本身（BillingVisibilityTests），无法证明「状态管理器真的照判据过滤」。
@MainActor
func runBillingFeatureBoundaryTests() {
    print("\n🧪 Testing 额度服务层跨 target 边界（快照可见性）...")
    testSnapshotVisibilityInFeatureTarget()
    print("✅ 额度服务层跨 target 边界 works")
}

// MARK: - 快照可见性

@MainActor
private func testSnapshotVisibilityInFeatureTarget() {
    let credentials = PreferencesBillingCredentialStore(storage: InMemoryStorage(),
                                                       secrets: InMemorySecretStorage(),
                                                       environment: [:])
    credentials.setCredential("sk-claude", for: "claude")

    // provider 取自迁入 feature target 的那 6 家：这两行能编译即证明模块边界可直达
    let claudeState = BillingMonitor.makeState(
        for: ClaudeBillingProvider(),
        instance: BillingInstanceID.defaultInstance(kindID: "claude", title: "Claude"),
        credentialStore: credentials)
    let codexState = BillingMonitor.makeState(
        for: CodexBillingProvider(),
        instance: BillingInstanceID.defaultInstance(kindID: "codex", title: "Codex"),
        credentialStore: credentials)

    // 1) 状态按凭据判定配置态，descriptor 的能力位取自 provider 协议（不是另抄一份）
    assertEqual(claudeState.isConfigured, true, "有凭据的 provider 为已配置")
    assertEqual(codexState.isConfigured, false, "无凭据的 provider 为未配置")
    assertEqual(claudeState.descriptor.id, "claude", "descriptor 的 id 即实例标识")
    assertEqual(claudeState.descriptor.symbolName, ClaudeBillingProvider().symbolName,
                "descriptor 的图标沿用 provider 声明值")
    assertEqual(claudeState.descriptor.supportsUsage, false, "只查额度的 provider 不带用量能力位")
    assertEqual(claudeState.balance == nil, true, "初始状态没有余额数据")

    // 2) 快照只留「已配置」：未配置的 provider 不占位，但仍计入启用总数（两种空态靠它区分）
    let snapshot = BillingMonitor.Snapshot.make(from: [claudeState, codexState],
                                                enabledProviderCount: 2)
    assertEqual(snapshot.states.map(\.descriptor.id), ["claude"], "未配置的 provider 被快照过滤掉")
    assertEqual(snapshot.enabledProviderCount, 2, "启用总数记录的是过滤前的数量")
    assertEqual(snapshot.state(for: "codex") == nil, true, "被过滤的 provider 查不到状态")
    assertEqual(snapshot.isEmpty, false, "留了一项就不是空态")
    assertEqual(snapshot.emptyReason == nil, true, "非空态没有空态原因")

    // 3) 暂停态（锁屏 / 休眠）随快照带出，且不改变可见性
    let paused = BillingMonitor.Snapshot.make(from: [claudeState, codexState],
                                              enabledProviderCount: 2, isPaused: true)
    assertEqual(paused.isPaused, true, "暂停态由数据层带给面板")
    assertEqual(paused.states.map(\.descriptor.id), ["claude"], "暂停不改变可见集合")

    // 4) 两种空态各有原因：有启用但都没配 / 一个启用的都没有
    let noneConfigured = BillingMonitor.Snapshot.make(from: [codexState], enabledProviderCount: 1)
    assertEqual(noneConfigured.isEmpty, true, "全未配置即整页空态")
    assertEqual(noneConfigured.emptyReason, BillingMonitor.BillingEmptyReason.noneConfigured,
                "有启用项但都没凭据 → 去设置页填 Key")
    assertEqual(BillingMonitor.Snapshot.make(from: [], enabledProviderCount: 0).emptyReason,
                BillingMonitor.BillingEmptyReason.noEnabledProvider,
                "没有任何启用项 → 去设置页启用")
}
