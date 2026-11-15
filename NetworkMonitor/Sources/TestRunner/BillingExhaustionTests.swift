import Foundation
import NetworkMonitorCore

// MARK: - 用尽 → 恢复 / 没用尽 → 静默

/// 用户原始意见的可执行口径：
/// - 场景 A：5 小时额度从 40% 掉到 0.4% 发一条用尽，重置回 100% 再发一条已恢复；
/// - 场景 B：额度只在 30% 徘徊、每 5 小时重置回 100% —— 一条通知都不发。
func runBillingExhaustionTests() {
    print("\n🧪 Testing 场景 A：用尽后窗口重置发「已恢复」...")
    testRecoveredAfterExhaustion()

    print("\n🧪 Testing 场景 B：没用尽的周期切换必须静默...")
    testSilentWithoutExhaustion()

    print("\n🧪 Testing 用尽后剩余回升到用尽线以上...")
    testRecoveredByRisingAboveLine()

    print("\n🧪 Testing 场景 C：多条额度同时用尽合并成一条...")
    testMergedExhaustedAcrossWindows()

    print("✅ Billing 用尽与恢复 works")
}

private let exhaustionBase = Date(timeIntervalSince1970: 1_800_000_000)

// MARK: - 场景 A

private func testRecoveredAfterExhaustion() {
    let high = recoveryEvaluate(recoveryBalance(remaining: 0.4, window: recoverySessionWindowA), [:])
    assertEqual(high.alerts.isEmpty, true, "40% 不提醒")

    let drained = recoveryEvaluate(recoveryBalance(remaining: 0.004, window: recoverySessionWindowA),
                                   high.state)
    assertEqual(drained.alerts.count, 1, "跌破用尽线发一条")
    assertEqual(drained.alerts.first?.kind ?? .threshold(0), .exhausted, "种类是用尽")
    assertEqual(drained.alerts.first?.title(providerName: "Claude") ?? "",
                "Claude · 5 小时额度已用尽", "用尽标题带窗口时长")
    assertEqual(drained.alerts.first?.windowTitle ?? "", "5 小时", "窗口名取 BillingQuotaWindow.title")
    assertEqual(drained.state["codex.session"]?.exhaustedCycleID ?? "",
                recoverySessionWindowA.cycleID, "用尽周期写进状态")

    // 5 小时后窗口重置回 100%：发一条「已恢复」
    let reset = recoveryEvaluate(recoveryBalance(remaining: 1.0, window: recoverySessionWindowB),
                                 drained.state, now: exhaustionBase.addingTimeInterval(18_000))
    assertEqual(reset.alerts.count, 1, "重置只发一条（不叠加回升）")
    let alert = reset.alerts[0]
    assertEqual(alert.kind, .recovered, "种类是恢复")
    assertEqual(alert.title(providerName: "Claude"), "Claude · 5 小时额度已恢复", "恢复标题带窗口时长")
    assertEqual(alert.bodyText.contains("已恢复至 100%"), true, "恢复正文写当前剩余")
    assertEqual(reset.state["codex.session"]?.exhaustedCycleID == nil, true, "恢复后清掉用尽记录")
    assertEqual(reset.state["codex.session"]?.notifiedThreshold ?? -1, 0, "恢复把已提醒阈值归零")

    let sameCycle = recoveryEvaluate(recoveryBalance(remaining: 0.95, window: recoverySessionWindowB),
                                     reset.state)
    assertEqual(sameCycle.alerts.isEmpty, true, "同一周期不重复通知恢复")

    let afterReset = recoveryEvaluate(recoveryBalance(remaining: 0.03, window: recoverySessionWindowB),
                                      sameCycle.state)
    assertEqual(afterReset.alerts.count, 1, "新周期内跌破阈值可提醒")
    assertEqual(afterReset.alerts.first?.kind ?? .recovered, .threshold(3), "跌破 3% 命中阈值 3")

    // 关闭恢复通知：用尽照发，恢复静默
    let off = recoveryEvaluate(recoveryBalance(remaining: 1.0, window: recoverySessionWindowB),
                               drained.state, options: BillingAlertOptions(notifyRecovered: false))
    assertEqual(off.alerts.isEmpty, true, "关闭恢复通知后不提醒")

    // 关闭用尽提醒：不产生用尽信号，后续也不会凭空恢复
    let noExhaust = recoveryEvaluate(recoveryBalance(remaining: 0.004, window: recoverySessionWindowA),
                                     [:], options: BillingAlertOptions(notifyExhausted: false,
                                                                       notifyThresholds: false))
    assertEqual(noExhaust.alerts.isEmpty, true, "关闭用尽提醒后低额度不打扰")
    let noRecover = recoveryEvaluate(recoveryBalance(remaining: 1.0, window: recoverySessionWindowB),
                                     noExhaust.state)
    assertEqual(noRecover.alerts.contains { $0.kind == .recovered }, false,
                "没发过用尽就不会发恢复（回升类另算）")
}

// MARK: - 场景 B

private func testSilentWithoutExhaustion() {
    // 30% 徘徊 → 每 5 小时重置回 100%，连续三个周期
    //
    // 重置用「重置时刻前进」的下一窗口：服务端真进入新周期时 resetsAt 会往前走，
    // 这也是「同一周期内 30% 跳到 100%」与「窗口切周期」的分界。
    var state: [String: BillingAlertState] = [:]
    let windows = [recoverySessionWindowA, recoverySessionWindowB, recoverySessionWindowC]
    var observed: [BillingAlert] = []
    for (index, window) in windows.enumerated() {
        let offset = exhaustionBase.addingTimeInterval(Double(index) * 18_000)
        let hover = recoveryEvaluate(recoveryBalance(remaining: 0.3, window: window), state, now: offset)
        observed.append(contentsOf: hover.alerts)
        state = hover.state
        let next = BillingQuotaWindow(kind: .session, duration: 18_000,
                                      resetsAt: window.resetsAt.addingTimeInterval(18_000))
        let reset = recoveryEvaluate(recoveryBalance(remaining: 1.0, window: next), state,
                                     now: offset.addingTimeInterval(60))
        observed.append(contentsOf: reset.alerts)
        state = reset.state
    }
    assertEqual(observed.isEmpty, true,
                "没用尽过的额度切周期完全静默（用户要的「不要每 5 小时发一次」）")
    assertEqual(state["codex.session"]?.exhaustedCycleID == nil, true, "全程没有用尽记录")
    assertEqual(state["codex.session"]?.lastResetNotifiedCycleID == nil, true, "也没有恢复通知记录")

    // 再切一个周期仍然静默
    let next = recoverySessionWindowC.resetsAt.addingTimeInterval(18_000)
    let many = recoveryEvaluate(recoveryBalance(remaining: 1.0,
                                               window: BillingQuotaWindow(kind: .session, duration: 18_000,
                                                                          resetsAt: next)), state)
    assertEqual(many.alerts.isEmpty, true, "再切一个周期仍然静默")
}

// MARK: - 用尽后回升

private func testRecoveredByRisingAboveLine() {
    let first = recoveryEvaluate(recoveryBalance(remaining: 0.5, window: nil), [:])
    let drained = recoveryEvaluate(recoveryBalance(remaining: 0.0, window: nil), first.state)
    assertEqual(drained.alerts.first?.kind ?? .threshold(0), .exhausted, "0% 发用尽")

    // 服务端补了额度但窗口没切：剩余回到 40% → 一条「已恢复」
    let refilled = recoveryEvaluate(recoveryBalance(remaining: 0.4, window: nil), drained.state)
    let recoveredKinds = refilled.alerts.filter { $0.kind == .recovered }
    assertEqual(recoveredKinds.count, 1, "回到用尽线以上发恢复")
    assertEqual(recoveredKinds.first?.title(providerName: "Codex") ?? "",
                "Codex · 会话额度已恢复", "无窗口信息时用额度行标题")
    assertEqual(refilled.state["codex.session"]?.exhaustedCycleID == nil, true, "恢复后清掉用尽记录")

    // 恢复不占回升冷却：同一轮之后仍可发回升通知
    assertEqual(refilled.state["codex.session"]?.lastRecoveryNotifiedAt == nil, true,
                "恢复不动回升冷却时间戳")
    let drop = recoveryEvaluate(recoveryBalance(remaining: 0.1, window: nil), refilled.state,
                                now: exhaustionBase.addingTimeInterval(600))
    let up = recoveryEvaluate(recoveryBalance(remaining: 0.35, window: nil), drop.state,
                              now: exhaustionBase.addingTimeInterval(700))
    assertEqual(up.alerts.contains { $0.kind == .balanceRecovered }, true, "恢复后回升通知照常")
}

// MARK: - 场景 C

/// Codex 的两个窗口同时用尽：评估器产出两条用尽，折叠成一条通知
private func testMergedExhaustedAcrossWindows() {
    let sessionWindow = BillingQuotaWindow(kind: .session, duration: 18_000,
                                          resetsAt: exhaustionBase.addingTimeInterval(18_000))
    let weeklyWindow = BillingQuotaWindow(kind: .weekly, duration: 604_800,
                                         resetsAt: exhaustionBase.addingTimeInterval(604_800))
    func balance(session: Double, weekly: Double) -> BillingBalance {
        BillingBalance(percentLimits: [
            BillingPercentLimit(id: "session", title: "会话", remainingFraction: session,
                                resetsAt: sessionWindow.resetsAt, window: sessionWindow),
            BillingPercentLimit(id: "weekly", title: "每周", remainingFraction: weekly,
                                resetsAt: weeklyWindow.resetsAt, window: weeklyWindow),
        ])
    }

    // 基线：两个窗口都还宽裕
    let baseline = recoveryEvaluate(balance(session: 0.5, weekly: 0.5), [:])
    assertEqual(baseline.alerts.isEmpty, true, "基线观测不提醒")

    // 只有每周用尽：单条，文案用「每周」
    let weeklyOnly = recoveryEvaluate(balance(session: 0.5, weekly: 0.004), baseline.state)
    let weeklyMessages = BillingAlertDigest.messages(for: weeklyOnly.alerts, providerName: "Codex")
    assertEqual(weeklyMessages.count, 1, "只用尽一个窗口发一条")
    assertEqual(weeklyMessages.first?.title ?? "", "Codex · 每周额度已用尽", "周额度用尽文案")

    // 5 小时窗口接着用尽：本轮只新增一条，合并后仍是一条通知
    let sessionOnly = recoveryEvaluate(balance(session: 0.002, weekly: 0.004), weeklyOnly.state)
    assertEqual(sessionOnly.alerts.filter { $0.kind == .exhausted }.count, 1, "新用尽的是 5 小时窗口")
    let singleMessages = BillingAlertDigest.messages(for: sessionOnly.alerts, providerName: "Codex")
    assertEqual(singleMessages.first?.title ?? "", "Codex · 5 小时额度已用尽", "单独用尽仍带窗口名")

    // 两个窗口同一轮同时用尽：两条 alert → 一条通知
    let both = recoveryEvaluate(balance(session: 0.002, weekly: 0.004), baseline.state)
    assertEqual(both.alerts.filter { $0.kind == .exhausted }.count, 2, "两个窗口各产出一条用尽")
    let messages = BillingAlertDigest.messages(for: both.alerts, providerName: "Codex")
    assertEqual(messages.count, 1, "同一 provider 同时用尽只弹一次窗")
    assertEqual(messages.first?.title ?? "", "Codex · 额度已用尽", "合并标题")
    assertEqual(messages.first?.body.contains("5 小时") ?? false, true, "合并正文列出 5 小时窗口")
    assertEqual(messages.first?.body.contains("每周") ?? false, true, "合并正文列出每周窗口")
}
