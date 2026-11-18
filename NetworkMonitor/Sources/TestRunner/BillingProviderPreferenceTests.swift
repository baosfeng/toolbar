import Foundation
import NetworkMonitorCore

// MARK: - 额度 provider 启用默认值 / 可用性

/// 用户口径：「额度的 provider 应该默认都是关闭的，配置了之后才能打开」。
/// 这里钉住三件事：缺键默认关闭、老用户（键存在且 true）不被静默下线、
/// 无凭据时开关不可开（判据是 Core 的纯函数，不在视图里散写）。
func runBillingProviderPreferenceTests() {
    print("\n🧪 Testing 额度 provider 默认关闭 / 老用户不回归...")
    testProviderDefaultDisabled()
    testLegacyEnabledProviderStaysOnline()

    print("\n🧪 Testing 无凭据不可开（BillingProviderAvailability）...")
    testProviderAvailability()
}

// MARK: - 默认关闭

private func testProviderDefaultDisabled() {
    let storage = InMemoryStorage()
    let preferences = BillingProviderPreferences(storage: storage)

    assertEqual(preferences.isEnabled("ollama"), false, "从未写过启用键 → 默认关闭")
    assertEqual(preferences.isEnabled("cursor::work"), false, "命名实例同样默认关闭")
    assertEqual(preferences.hasExplicitChoice("ollama"), false, "默认关闭不是「显式选择」")
    assertEqual(storage.object(forKey: BillingProviderPreferences.storageKey(for: "ollama")) == nil,
                true, "默认关闭不落盘（缺键即默认，避免写一堆 false）")

    assertEqual(BillingProviderPreferences.filterEnabled(["ollama", "codex"], preferences: preferences),
                [], "默认关闭时没有实例参与查询")

    preferences.setEnabled(true, for: "ollama")
    assertEqual(preferences.isEnabled("ollama"), true, "显式打开后生效")
    assertEqual(preferences.hasExplicitChoice("ollama"), true, "显式打开算「用户的选择」")

    // 删实例 → 重建同名实例回到默认关闭
    preferences.removeEnabled(for: "ollama")
    assertEqual(preferences.isEnabled("ollama"), false, "removeEnabled 后回到默认关闭")
    assertEqual(preferences.hasExplicitChoice("ollama"), false, "removeEnabled 同时清掉「显式选择」标记")
    assertEqual(storage.object(forKey: BillingProviderPreferences.storageKey(for: "ollama")) == nil,
                true, "removeEnabled 真的删掉了键")
}

// MARK: - 老用户不回归

private func testLegacyEnabledProviderStaysOnline() {
    // 老版本装了 provider 并显式启用：键存在且为 true
    let storage = InMemoryStorage()
    storage.set(true, forKey: BillingProviderPreferences.storageKey(for: "cursor"))
    storage.set(true, forKey: BillingProviderPreferences.storageKey(for: "cursor::work"))
    let preferences = BillingProviderPreferences(storage: storage)

    assertEqual(preferences.isEnabled("cursor"), true, "老用户已启用（键存在为 true）升级后保持启用")
    assertEqual(preferences.isEnabled("cursor::work"), true, "老用户已启用的命名实例同样保持启用")
    assertEqual(BillingProviderPreferences.filterEnabled(["cursor", "cursor::work", "ollama"],
                                                         preferences: preferences),
                ["cursor", "cursor::work"],
                "老用户已启用的继续查询，从未写过的才按默认关闭")

    // 老版本显式关掉过：仍然关着（不能被默认值翻转成开）
    let offStorage = InMemoryStorage()
    offStorage.set(false, forKey: BillingProviderPreferences.storageKey(for: "ollama"))
    let offPreferences = BillingProviderPreferences(storage: offStorage)
    assertEqual(offPreferences.isEnabled("ollama"), false, "老用户显式关闭的保持关闭")
    assertEqual(offPreferences.hasExplicitChoice("ollama"), true, "显式关闭也算用户的选择")
}

// MARK: - 可用性

private func testProviderAvailability() {
    assertEqual(BillingProviderAvailability.canEnable(hasCredential: false, isEnabled: false), false,
                "无凭据 + 未启用 → 不可打开")
    assertEqual(BillingProviderAvailability.canEnable(hasCredential: false, isEnabled: true), false,
                "无凭据 + 已启用（凭据被清）→ 开关同样不可操作")
    assertEqual(BillingProviderAvailability.canEnable(hasCredential: true, isEnabled: false), true,
                "有凭据 → 可以打开")
    assertEqual(BillingProviderAvailability.canEnable(hasCredential: true, isEnabled: true), true,
                "有凭据 + 已开 → 可以关掉")

    assertEqual(BillingProviderAvailability.disabledHint(hasCredential: false, isEnabled: false),
                "先填凭据，再打开开关", "无凭据时给出「先填凭据」说明")
    assertEqual(BillingProviderAvailability.disabledHint(hasCredential: true, isEnabled: false), nil,
                "有凭据时不给多余说明")

    assertEqual(BillingProviderAvailability.isEnabledWithoutCredential(hasCredential: false, isEnabled: true),
                true, "已启用但凭据被清 → 需要提示")
    assertEqual(BillingProviderAvailability.isEnabledWithoutCredential(hasCredential: true, isEnabled: true),
                false, "正常启用不提示")
}
