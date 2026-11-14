import Foundation
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 屏幕活动状态机（锁屏 / 休眠暂停额度刷新的判据）

/// 复现「额度页停在旧数据且永不恢复」的判据单测
///
/// 根因：`ScreenActivityMonitor` 只被局部变量引用时立即释放，而通知中心只强持 observer 闭包，
/// 闭包里的 `[weak self]` 此后恒为 nil —— pause / resume 再也不会被调用，额度刷新永远停在
/// 上一个状态（现场表现就是「额度没用了」）。本文件覆盖三条判据：
/// 1. 状态去重：同一状态重复投递只派发一次（否则每次唤醒都强制拉一轮接口，打满 provider 限流）；
/// 2. 状态迁移：不可用 → 暂停、恢复 → 立即刷新；
/// 3. 暂停态可见：快照带 `isPaused`，面板文案说清「为什么不动」。
func runScreenActivityRelayTests() {
    print("\n🧪 Testing 屏幕活动状态机（暂停 / 恢复去重）...")
    testScreenActivityRelayBaseline()
    testScreenActivityRelayTransitions()
    testScreenActivityRelayDuplicates()

    print("\n🧪 Testing 额度页暂停态文案（不再装作在查询）...")
    testBillingRefreshStatusText()

    print("\n🧪 Testing 额度卡片状态胶囊（四档，含「未刷新」）...")
    testProviderStatusChip()
}

// MARK: - 状态机

private func testScreenActivityRelayBaseline() {
    var relay = ScreenActivityRelay()
    assertEqual(relay.hasBaseline, false, "初始没有基准")
    assertEqual(relay.consume(active: true), .none,
                "首次判定为活跃不派发：启动即正常，无需额外刷新")
    assertEqual(relay.hasBaseline, true, "首次判定后即有基准")

    var lockedAtLaunch = ScreenActivityRelay()
    assertEqual(lockedAtLaunch.consume(active: false), .paused,
                "开机自启时屏幕仍锁着 → 必须立刻进暂停态，否则会先空打一轮请求")
}

private func testScreenActivityRelayTransitions() {
    var relay = ScreenActivityRelay()
    _ = relay.consume(active: true)
    assertEqual(relay.consume(active: false), .paused, "活跃 → 不可用：暂停")
    assertEqual(relay.consume(active: true), .resumed, "不可用 → 活跃：恢复并强制刷新一次")
    assertEqual(relay.consume(active: false), .paused, "再次进入不可用：暂停")
}

private func testScreenActivityRelayDuplicates() {
    var relay = ScreenActivityRelay()
    _ = relay.consume(active: false)
    assertEqual(relay.consume(active: false), .none,
                "显示器休眠 + 系统休眠先后到达：同一状态只暂停一次")
    _ = relay.consume(active: true)
    assertEqual(relay.consume(active: true), .none,
                "解锁通知 + 30 秒自检重叠：同一状态只恢复一次（每次恢复都强制拉接口）")

    // 连续重复投递只能产生 1 次动作，否则 provider 限流会被打满
    var counting = ScreenActivityRelay()
    var events = 0
    for _ in 0..<100 where counting.consume(active: false) != .none { events += 1 }
    assertEqual(events, 1, "100 次同一状态投递只派发 1 次动作")
}

// MARK: - 状态胶囊四档

private func testProviderStatusChip() {
    // 出错优先于一切：有错误文案时不能显示「正常」
    assertEqual(BillingProviderStatusLogic.kind(errorMessage: "网络错误", remainingFractions: [0.9],
                                               isLoading: false, hasBalance: true), .error,
                "有错误文案 → 出错（哪怕余额还在）")

    // 限流：任一窗口低于 20% 即告警（多窗口取最低的那个）
    assertEqual(BillingProviderStatusLogic.kind(errorMessage: nil, remainingFractions: [0.95, 0.11],
                                               isLoading: false, hasBalance: true), .warn,
                "任一窗口剩余低于 20% → 限流")
    assertEqual(BillingProviderStatusLogic.kind(errorMessage: nil, remainingFractions: [0.2],
                                               isLoading: false, hasBalance: true), .ok,
                "恰好 20% 不算限流（边界值不误报）")

    // 查询中优先于「未刷新」：正在查的时候别催用户
    assertEqual(BillingProviderStatusLogic.kind(errorMessage: nil, remainingFractions: [],
                                               isLoading: true, hasBalance: false), .loading,
                "正在请求 → 查询中")

    // 本次修复点：从未拿到过数据时必须说「未刷新」，不能顶着「正常」
    assertEqual(BillingProviderStatusLogic.kind(errorMessage: nil, remainingFractions: [],
                                               isLoading: false, hasBalance: false), .idle,
                "无数据且未在请求 → 未刷新（旧实现会误显示「正常」）")
    assertEqual(BillingProviderStatusLogic.text(.idle), "未刷新", "未刷新档的文案")

    // 有数据且无错误 → 正常
    assertEqual(BillingProviderStatusLogic.kind(errorMessage: nil, remainingFractions: [],
                                               isLoading: false, hasBalance: true), .ok,
                "有余额数据且无错误 → 正常")
}

// MARK: - 暂停态文案

private func testBillingRefreshStatusText() {
    // 暂停态：必须说清「等亮屏」，不能显示「实时 <旧时间>」误导用户以为还在查
    assertEqual(BillingRefreshStatusLogic.clockText(isPaused: true, latestStamp: "12:34"),
                "已暂停 · 恢复亮屏后自动刷新", "暂停态 Hero 时钟给原因与出路")
    assertEqual(BillingRefreshStatusLogic.bandText(isPaused: true),
                "已暂停", "页脚只写「已暂停」：长文案会把相邻「单位」挤成省略号")
    assertEqual(BillingRefreshStatusLogic.bandWarns(isPaused: true), true, "暂停时状态带上告警色")

    // 正常态：从未刷新过时不拼「实时 —」
    assertEqual(BillingRefreshStatusLogic.clockText(isPaused: false, latestStamp: "—"),
                "尚未刷新", "从未刷新过 → 尚未刷新（不写成「实时 —」）")
    assertEqual(BillingRefreshStatusLogic.clockText(isPaused: false, latestStamp: "12:34"),
                "实时 12:34", "正常刷新过 → 实时 + 时分")
    assertEqual(BillingRefreshStatusLogic.bandText(isPaused: false), "正常", "正常态状态带写「正常」")
    assertEqual(BillingRefreshStatusLogic.bandWarns(isPaused: false), false, "正常态不上告警色")
}