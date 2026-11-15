import Foundation
import NetworkMonitorCore

// MARK: - 额度阈值与用尽提醒测试

/// 覆盖阈值命中的边界、用尽信号（唯一的低额度硬信号）、去重、断崖跳变与偏低抑制
func runBillingAlertTests() {
    print("\n🧪 Testing BillingAlertThresholds...")
    testAlertThresholds()

    print("\n🧪 Testing 额度用尽提醒（去重 / 断崖 / 抑制）...")
    testExhaustedAlerts()

    print("\n🧪 Testing 偏低预告与回升（既有口径）...")
    testThresholdPreview()

    print("\n🧪 Testing 多条额度同时用尽合并成一条（场景 C）...")
    testMergedExhaustedMessages()

    print("✅ Billing 额度提醒 works")
}

private let alertBase = Date(timeIntervalSince1970: 1_800_000_000)

private func alertLimit(_ id: String, _ title: String, _ remaining: Double,
                        resetAt: Date? = alertBase) -> BillingPercentLimit {
    BillingPercentLimit(id: id, title: title, remainingFraction: remaining, resetsAt: resetAt)
}

private func alertBalance(_ limits: [BillingPercentLimit]) -> BillingBalance {
    BillingBalance(percentLimits: limits)
}

private func evaluateAlert(_ balance: BillingBalance,
                            state: [String: BillingAlertState],
                            providerID: String = "ollama",
                            options: BillingAlertOptions = BillingAlertOptions())
    -> (alerts: [BillingAlert], state: [String: BillingAlertState]) {
    BillingAlertEvaluator.evaluate(balance: balance, providerID: providerID,
                                   state: state, now: alertBase, options: options)
}

private func testAlertThresholds() {
    assertEqual(BillingAlertThresholds.reachedThreshold(remainingFraction: 0.06), nil, "6% 未到阈值")
    assertEqual(BillingAlertThresholds.reachedThreshold(remainingFraction: 0.05), 5, "5% 命中 5")
    assertEqual(BillingAlertThresholds.reachedThreshold(remainingFraction: 0.037), 4, "3.7% 命中 4")
    assertEqual(BillingAlertThresholds.reachedThreshold(remainingFraction: 0.012), 2, "1.2% 命中 2")
    // 0.5% 仍是「最近跨越的偏低档」（2%），但评估器会先用尽分支接管，不会发出偏低提醒
    assertEqual(BillingAlertThresholds.reachedThreshold(remainingFraction: -0.1), nil, "负值不命中")

    assertEqual(BillingAlertThresholds.isExhausted(remainingFraction: 0.004), true, "0.4% 已在用尽线内")
    assertEqual(BillingAlertThresholds.isExhausted(remainingFraction: 0.01), true, "1% 正好到用尽线")
    assertEqual(BillingAlertThresholds.isExhausted(remainingFraction: 0.0101), false, "1.01% 未到用尽线")
    assertEqual(BillingAlertThresholds.isExhausted(remainingFraction: 0), true, "0% 用尽")
    assertEqual(BillingAlertThresholds.isExhausted(remainingFraction: -0.2), true, "负值按 0 处理")
}

private func testExhaustedAlerts() {
    // 1) 40% → 0.4%：只在跌破用尽线时提醒一次
    let high = evaluateAlert(alertBalance([alertLimit("session", "会话", 0.4)]), state: [:])
    assertEqual(high.alerts.isEmpty, true, "40% 不提醒")
    let drained = evaluateAlert(alertBalance([alertLimit("session", "会话", 0.004)]), state: high.state)
    assertEqual(drained.alerts.count, 1, "跌破用尽线提醒一次")
    assertEqual(drained.alerts.first?.kind ?? .threshold(0), .exhausted, "种类是用尽")
    assertEqual(drained.alerts.first?.title(providerName: "Ollama") ?? "",
                "Ollama · 会话额度已用尽", "无窗口信息时用额度行标题")
    assertEqual(drained.alerts.first?.bodyText.contains("剩余 0.4%") ?? false, true, "正文写剩余原值")
    assertNotNil(drained.state["ollama.session"]?.exhaustedCycleID, "记录用尽周期")

    // 2) 同周期再观测 0.3%：不重发
    let again = evaluateAlert(alertBalance([alertLimit("session", "会话", 0.003)]), state: drained.state)
    assertEqual(again.alerts.isEmpty, true, "同一周期不重复发用尽")

    // 3) 断崖：20% 直接掉到 0.4% 只发一条用尽，不连发 5/4/3/2/1
    let cliffHigh = evaluateAlert(alertBalance([alertLimit("session", "会话", 0.2)]), state: [:])
    let cliff = evaluateAlert(alertBalance([alertLimit("session", "会话", 0.004)]), state: cliffHigh.state)
    assertEqual(cliff.alerts.count, 1, "断崖只发一条")
    assertEqual(cliff.alerts.first?.kind ?? .threshold(0), .exhausted, "断崖发的是用尽")

    // 4) 先 3% 预告、再跌破用尽线：预告 + 用尽各一条
    let low = evaluateAlert(alertBalance([alertLimit("session", "会话", 0.03)]), state: [:])
    assertEqual(low.alerts.first?.kind ?? .exhausted, .threshold(3), "3% 只发偏低预告")
    let exhaustedAfterLow = evaluateAlert(alertBalance([alertLimit("session", "会话", 0.008)]),
                                          state: low.state)
    assertEqual(exhaustedAfterLow.alerts.count, 1, "再跌破用尽线补一条")
    assertEqual(exhaustedAfterLow.alerts.first?.kind ?? .threshold(0), .exhausted, "补的是用尽")

    // 5) 本周期发过用尽后，不再补发更低档的偏低
    let silentOptions = BillingAlertOptions(notifyRecovered: false)
    let once = evaluateAlert(alertBalance([alertLimit("session", "会话", 0.009)]),
                             state: [:], options: silentOptions)
    assertEqual(once.alerts.count, 1, "0.9% 发用尽")
    let backUp = evaluateAlert(alertBalance([alertLimit("session", "会话", 0.03)]),
                               state: once.state, options: silentOptions)
    assertEqual(backUp.alerts.isEmpty, true, "用尽后本周期不再补发偏低")

    // 6) 边界：1% 算用尽，2% 只算偏低
    let boundary = evaluateAlert(alertBalance([alertLimit("session", "会话", 0.01)]), state: [:])
    assertEqual(boundary.alerts.first?.kind ?? .threshold(0), .exhausted, "1% 算用尽")
    let above = evaluateAlert(alertBalance([alertLimit("session", "会话", 0.02)]), state: [:])
    assertEqual(above.alerts.first?.kind ?? .exhausted, .threshold(2), "2% 只算偏低")
}

private func testThresholdPreview() {
    func makeBalance(session: Double, weekly: Double, resetAt: Date = alertBase) -> BillingBalance {
        alertBalance([alertLimit("session", "会话", session, resetAt: resetAt),
                      alertLimit("weekly", "每周", weekly, resetAt: resetAt)])
    }

    let first = evaluateAlert(makeBalance(session: 0.04, weekly: 0.012), state: [:])
    assertEqual(first.alerts.count, 2, "首次命中两条偏低预告")
    let sessionAlert = first.alerts.first { $0.resourceTitle == "会话" }
    assertEqual(sessionAlert?.threshold ?? -1, 4, "会话命中阈值 4")
    assertEqual(sessionAlert?.bodyText.contains("剩余 4%") ?? false, true, "正文按原值展示 4%")
    assertEqual(sessionAlert?.title(providerName: "Ollama") ?? "", "Ollama · 会话额度偏低", "分级标题")
    assertEqual(first.state["ollama.session"]?.notifiedThreshold ?? -1, 4, "会话状态已记录")
    assertEqual(first.state["ollama.weekly"]?.notifiedThreshold ?? -1, 2, "每周状态已记录")

    let repeatRun = evaluateAlert(makeBalance(session: 0.04, weekly: 0.012), state: first.state)
    assertEqual(repeatRun.alerts.isEmpty, true, "同阈值不重复提醒")

    let lower = evaluateAlert(makeBalance(session: 0.03, weekly: 0.012), state: repeatRun.state)
    assertEqual(lower.alerts.count, 1, "跌破更低阈值再提醒")
    assertEqual(lower.alerts.first?.threshold ?? -1, 3, "命中阈值 3")

    // 周期切换但从未用尽：只重新预告偏低，不发恢复
    let newReset = alertBase.addingTimeInterval(86_400 * 30)
    let newCycle = evaluateAlert(makeBalance(session: 0.03, weekly: 0.012, resetAt: newReset),
                                 state: lower.state)
    assertEqual(newCycle.alerts.contains { $0.kind == .recovered }, false,
                "没用尽过的额度切周期不发恢复")
    assertEqual(newCycle.alerts.count, 2, "新周期偏低重新预告")

    // 回升：无窗口信息时按额度行标题兜底
    let base = evaluateAlert(alertBalance([alertLimit("session", "会话", 0.1, resetAt: nil)]), state: [:])
    assertEqual(base.alerts.isEmpty, true, "基线观测不提醒")
    let up = evaluateAlert(alertBalance([alertLimit("session", "会话", 0.25, resetAt: nil)]),
                           state: base.state)
    assertEqual(up.alerts.count, 1, "回升达到阈值提醒")
    assertEqual(up.alerts.first?.kind ?? .exhausted, .balanceRecovered, "种类是回升")
    assertEqual(up.alerts.first?.title(providerName: "Ollama") ?? "", "Ollama · 会话额度回升", "回升标题")
    assertEqual(up.alerts.first?.bodyText ?? "", "剩余 10% → 25%（+15 个百分点）", "回升正文带前后对比")

    let drop = evaluateAlert(alertBalance([alertLimit("session", "会话", 0.1, resetAt: nil)]), state: up.state)
    let cooling = evaluateAlert(alertBalance([alertLimit("session", "会话", 0.3, resetAt: nil)]),
                                state: drop.state)
    assertEqual(cooling.alerts.isEmpty, true, "冷却期内不重复提醒回升")

    // 内含额度：4% 走同一套偏低逻辑
    let period = BillingPeriod(start: alertBase.addingTimeInterval(-86_400),
                               end: alertBase.addingTimeInterval(86_400 * 20))
    let includedOnly = BillingBalance(included: BillingIncludedBalance(remainingUSD: 4,
                                                                   allowanceUSD: 100,
                                                                   period: period))
    let includedRun = evaluateAlert(includedOnly, state: [:])
    assertEqual(includedRun.alerts.count, 1, "内含额度命中提醒")
    assertEqual(includedRun.alerts.first?.title(providerName: "Ollama") ?? "",
                "Ollama · 内含额度偏低", "内含额度分级标题")
}

// MARK: - 场景 C：多条额度同时用尽

private func testMergedExhaustedMessages() {
    let reset = alertBase
    func exhausted(_ title: String, window: String, percent: Double) -> BillingAlert {
        BillingAlert(key: "codex.\(title)", providerID: "codex", resourceTitle: title,
                     kind: .exhausted, remainingPercent: percent, recoveredPercent: nil,
                     windowTitle: window, resetAt: reset)
    }
    let session = exhausted("会话", window: "5 小时", percent: 0.4)
    let weekly = exhausted("每周", window: "每周", percent: 0.8)

    let merged = BillingAlertDigest.messages(for: [session, weekly], providerName: "Codex")
    assertEqual(merged.count, 1, "两条同时用尽合并成一条通知")
    assertEqual(merged.first?.kind ?? .threshold(0), .exhausted, "合并后的种类仍是用尽")
    assertEqual(merged.first?.title ?? "", "Codex · 额度已用尽", "合并标题不带单条窗口名")
    assertEqual(merged.first?.body ?? "", "5 小时、每周均已用尽（剩余 0.4% / 0.8%）",
                "正文列出两条窗口名与剩余")

    let single = BillingAlertDigest.messages(for: [session], providerName: "Codex")
    assertEqual(single.count, 1, "单条用尽只发一条")
    assertEqual(single.first?.title ?? "", "Codex · 5 小时额度已用尽", "单条用尽标题带窗口名")

    // 用尽 + 偏低同时出现：用尽排最前，偏低各自成条（数值不同，不合并）
    let low = BillingAlert(key: "codex.weekly", providerID: "codex", resourceTitle: "每周",
                          kind: .threshold(4), remainingPercent: 4, recoveredPercent: nil,
                          windowTitle: "每月", resetAt: reset)
    let mixed = BillingAlertDigest.messages(for: [low, session], providerName: "Codex")
    assertEqual(mixed.count, 2, "用尽与偏低各成一条")
    assertEqual(mixed.first?.kind ?? .threshold(0), .exhausted, "用尽排最前")
    assertEqual(mixed.last?.title ?? "", "Codex · 每周额度偏低", "偏低标题沿用额度行")
}
