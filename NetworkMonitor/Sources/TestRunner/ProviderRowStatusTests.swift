import Foundation
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 设置页行状态口径 + 窗口清单

/// 默认关闭后「未配置」不再是异常态：状态点的色调与文案必须跟着变，
/// 且「该列哪些窗口」要有确定的回落顺序（实际观测 → provider 声明 → 四档兜底）。
func runProviderRowStatusAndWindowInventoryTests() {
    print("\n🧪 Testing 设置页行状态口径...")
    testProviderRowStatus()

    print("\n🧪 Testing 恢复通知窗口清单（观测 / 声明 / 兜底）...")
    testWindowKindInventory()
}

private func testProviderRowStatus() {
    let off = ProviderRowStatusLogic.status(isEnabled: false, isConfigured: false,
                                            fromEnvironment: false, errorMessage: nil,
                                            refreshText: "尚未刷新")
    assertEqual(off.tone, .idle, "默认关闭 + 未配置 → 中性色，不带告警")
    assertEqual(off.text, "未配置 · 先填凭据才能打开", "默认关闭 + 未配置 → 说明先填凭据")

    let configuredOff = ProviderRowStatusLogic.status(isEnabled: false, isConfigured: true,
                                                      fromEnvironment: false, errorMessage: nil,
                                                      refreshText: "刚刚刷新")
    assertEqual(configuredOff.tone, .idle, "已配置但停用 → 中性色")
    assertEqual(configuredOff.text, "已配置 · 已停用", "已配置但停用 → 已停用")

    let orphan = ProviderRowStatusLogic.status(isEnabled: true, isConfigured: false,
                                               fromEnvironment: false, errorMessage: nil,
                                               refreshText: "尚未刷新")
    assertEqual(orphan.tone, .warn, "已启用但凭据被清 → 告警色")
    assertEqual(orphan.text, "已启用 · 凭据已清除，先填凭据", "已启用但凭据被清 → 提示补凭据")

    let ok = ProviderRowStatusLogic.status(isEnabled: true, isConfigured: true,
                                           fromEnvironment: false, errorMessage: nil,
                                           refreshText: "3 分钟前刷新")
    assertEqual(ok.tone, .ok, "正常 → 达标色")
    assertEqual(ok.text, "已配置 · 3 分钟前刷新", "正常 → 已配置 + 时效")

    let envOnly = ProviderRowStatusLogic.status(isEnabled: true, isConfigured: true,
                                                fromEnvironment: true, errorMessage: nil,
                                                refreshText: "刚刚刷新")
    assertEqual(envOnly.text, "已配置（环境变量） · 刚刚刷新", "环境变量回退时标注来源")

    let failed = ProviderRowStatusLogic.status(isEnabled: true, isConfigured: true,
                                               fromEnvironment: false, errorMessage: "凭据无效",
                                               refreshText: "刚刚刷新")
    assertEqual(failed.tone, .warn, "有错误 → 告警色")
}

private func testWindowKindInventory() {
    let session = BillingQuotaWindow(kind: .session, duration: 18_000,
                                     resetsAt: Date(timeIntervalSince1970: 1_800_000_000))
    let weekly = BillingQuotaWindow(kind: .weekly, duration: 604_800,
                                    resetsAt: Date(timeIntervalSince1970: 1_800_000_000))
    let balance = BillingBalance(percentLimits: [
        BillingPercentLimit(id: "session", title: "5 小时", remainingFraction: 0.5,
                            resetsAt: session.resetsAt, window: session),
        BillingPercentLimit(id: "weekly", title: "每周", remainingFraction: 0.5,
                            resetsAt: weekly.resetsAt, window: weekly),
    ])
    assertEqual(BillingWindowKindInventory.observed(in: balance), [.session, .weekly],
                "只列实际出现过的窗口种类（按出现顺序）")
    assertEqual(BillingWindowKindInventory.observed(in: nil), [], "没有余额数据时不给观测结果")

    let nilWindow = BillingBalance(percentLimits: [
        BillingPercentLimit(id: "credits", title: "余额", remainingFraction: 0.5, resetsAt: nil),
    ])
    assertEqual(BillingWindowKindInventory.observed(in: nilWindow), [],
                "window == nil 的额度不贡献窗口种类")

    let period = BillingPeriod(start: Date(timeIntervalSince1970: 1_800_000_000),
                               end: Date(timeIntervalSince1970: 1_802_600_000))
    let included = BillingBalance(included: BillingIncludedBalance(remainingUSD: 5, allowanceUSD: 10,
                                                                   period: period))
    assertEqual(BillingWindowKindInventory.observed(in: included), [.monthly],
                "内含额度的计费周期按月度窗口计入")

    assertEqual(BillingWindowKindInventory.options(observed: [.weekly], declared: [.session, .monthly]),
                [.weekly], "观测优先于声明")
    assertEqual(BillingWindowKindInventory.options(observed: [], declared: [.session, .weekly]),
                [.session, .weekly], "取不到观测时用 provider 声明")
    assertEqual(BillingWindowKindInventory.options(observed: [], declared: []),
                [.session, .daily, .weekly, .monthly], "都拿不到时列四档兜底（不含 custom）")
    assertEqual(BillingWindowKindInventory.options(observed: [.custom], declared: [.weekly]),
                [.weekly], "custom 不进勾选清单（没有稳定标题）")
    assertEqual(BillingWindowKindInventory.options(observed: [.session, .session], declared: []),
                [.session], "观测结果去重")
    assertEqual(BillingWindowKindInventory.options(balance: balance, declared: []),
                [.session, .weekly], "便捷入口按余额取窗口")
}
