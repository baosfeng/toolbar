import Foundation
import NetworkMonitorCore

// MARK: - 额度阈值提醒测试

/// 覆盖阈值命中的边界、去重、跳变、周期重置与回升清空
func runBillingAlertTests() {
    print("\n🧪 Testing BillingAlertThresholds...")
    testAlertThresholds()

    print("\n🧪 Testing BillingAlertEvaluator...")
    testAlertEvaluator()

    print("✅ Billing 额度提醒 works")
}

private func testAlertThresholds() {
    assertEqual(BillingAlertThresholds.reachedThreshold(remainingFraction: 0.06), nil, "6% 未到阈值")
    assertEqual(BillingAlertThresholds.reachedThreshold(remainingFraction: 0.05), 5, "5% 命中 5")
    assertEqual(BillingAlertThresholds.reachedThreshold(remainingFraction: 0.049), 5, "4.9% 命中 5")
    assertEqual(BillingAlertThresholds.reachedThreshold(remainingFraction: 0.04), 4, "4% 命中 4")
    assertEqual(BillingAlertThresholds.reachedThreshold(remainingFraction: 0.037), 4, "3.7% 命中 4")
    assertEqual(BillingAlertThresholds.reachedThreshold(remainingFraction: 0.02), 2, "2% 命中 2")
    assertEqual(BillingAlertThresholds.reachedThreshold(remainingFraction: 0.012), 2, "1.2% 命中 2")
    assertEqual(BillingAlertThresholds.reachedThreshold(remainingFraction: 0.01), 1, "1% 命中 1")
    assertEqual(BillingAlertThresholds.reachedThreshold(remainingFraction: 0.005), 1, "0.5% 命中 1")
    assertEqual(BillingAlertThresholds.reachedThreshold(remainingFraction: 0), 1, "0% 命中 1")
    assertEqual(BillingAlertThresholds.reachedThreshold(remainingFraction: -0.1), nil, "负值不命中")
}

private func testAlertEvaluator() {
    let reset = Date(timeIntervalSince1970: 1_800_000_000)
    let period = BillingPeriod(start: reset.addingTimeInterval(-86_400),
                               end: reset.addingTimeInterval(86_400 * 20))

    func makeBalance(session: Double, weekly: Double, included: Double = 0.3) -> BillingBalance {
        BillingBalance(included: BillingIncludedBalance(remainingUSD: included * 100,
                                                        allowanceUSD: 100,
                                                        period: period),
                       purchasedUSD: 10,
                       percentLimits: [
                        BillingPercentLimit(id: "session", title: "会话",
                                            remainingFraction: session, resetsAt: reset),
                        BillingPercentLimit(id: "weekly", title: "每周",
                                            remainingFraction: weekly, resetsAt: reset),
                       ])
    }

    // 首次：会话 4% → 提醒；每周 1.2% → 提醒 1 档；内含 30% → 不提醒
    let first = BillingAlertEvaluator.evaluate(balance: makeBalance(session: 0.04, weekly: 0.012),
                                               providerID: "ollama",
                                               state: [:])
    assertEqual(first.alerts.count, 2, "首次命中两条提醒")
    let sessionAlert = first.alerts.first { $0.resourceTitle == "会话" }
    assertEqual(sessionAlert?.threshold ?? -1, 4, "会话命中阈值 4")
    assertEqual(sessionAlert?.remainingPercent ?? -1, 4, "会话剩余 4%")
    assertEqual(sessionAlert?.title(providerName: "Ollama") ?? "", "Ollama · 会话额度偏低", "分级标题")
    assertEqual(sessionAlert?.bodyText.contains("重置") ?? false, true, "正文带重置时间")
    assertEqual(first.state["ollama.session"]?.notifiedThreshold ?? -1, 4, "会话状态已记录")
    assertEqual(first.state["ollama.weekly"]?.notifiedThreshold ?? -1, 2, "每周状态已记录")
    assertEqual(first.state["ollama.included"] == nil, true, "内含未到阈值不记录")

    // 同状态再次评估：不重复提醒
    let repeatRun = BillingAlertEvaluator.evaluate(balance: makeBalance(session: 0.04, weekly: 0.012),
                                                  providerID: "ollama",
                                                  state: first.state)
    assertEqual(repeatRun.alerts.isEmpty, true, "同阈值不重复提醒")

    // 会话降到 3%：再提醒一次（更低阈值）
    let lower = BillingAlertEvaluator.evaluate(balance: makeBalance(session: 0.03, weekly: 0.012),
                                               providerID: "ollama",
                                               state: repeatRun.state)
    assertEqual(lower.alerts.count, 1, "跌破更低阈值再提醒")
    assertEqual(lower.alerts.first?.threshold ?? -1, 3, "命中阈值 3")
    assertEqual(lower.state["ollama.session"]?.notifiedThreshold ?? -1, 3, "状态更新为 3")

    // 一次跳变跨多档：6% → 3% 只发最低档一条
    let jump = BillingAlertEvaluator.evaluate(balance: makeBalance(session: 0.06, weekly: 0.012),
                                              providerID: "ollama", state: [:])
    assertEqual(jump.alerts.first { $0.resourceTitle == "会话" } == nil, true, "6% 不提醒")
    let afterJump = BillingAlertEvaluator.evaluate(balance: makeBalance(session: 0.03, weekly: 0.012),
                                                   providerID: "ollama", state: jump.state)
    assertEqual(afterJump.alerts.count, 1, "跳变只发一条")
    assertEqual(afterJump.alerts.first?.threshold ?? -1, 3, "跳变命中 3")

    // 周期变化（重置时间改变）：同阈值重新提醒
    let newReset = reset.addingTimeInterval(86_400 * 30)
    let newPeriod = BillingPeriod(start: newReset.addingTimeInterval(-86_400),
                                  end: newReset.addingTimeInterval(86_400 * 20))
    let newCycle = BillingBalance(included: nil, purchasedUSD: 10,
                                  percentLimits: [
                                    BillingPercentLimit(id: "session", title: "会话",
                                                        remainingFraction: 0.04, resetsAt: newReset),
                                  ])
    let afterCycle = BillingAlertEvaluator.evaluate(balance: newCycle,
                                                    providerID: "ollama",
                                                    state: lower.state)
    assertEqual(afterCycle.alerts.count, 1, "周期变化后重新提醒")
    assertEqual(afterCycle.state["ollama.session"]?.notifiedThreshold ?? -1, 4, "新周期状态重置为 4")

    // 回升到 5% 以上：清空记录，下次下降可再次提醒
    let recovered = BillingAlertEvaluator.evaluate(balance: makeBalance(session: 0.2, weekly: 0.012),
                                                   providerID: "ollama",
                                                   state: lower.state)
    assertEqual(recovered.alerts.isEmpty, true, "回升不提醒")
    assertEqual(recovered.state["ollama.session"]?.notifiedThreshold ?? -1, 0, "回升后阈值记录清零")
    _ = newPeriod

    // 内含额度：4% 提醒「内含额度剩余 4%」
    let includedOnly = BillingBalance(included: BillingIncludedBalance(remainingUSD: 4,
                                                                       allowanceUSD: 100,
                                                                       period: period))
    let includedRun = BillingAlertEvaluator.evaluate(balance: includedOnly,
                                                     providerID: "ollama",
                                                     state: [:])
    assertEqual(includedRun.alerts.count, 1, "内含额度命中提醒")
    assertEqual(includedRun.alerts.first?.title(providerName: "Ollama") ?? "",
                "Ollama · 内含额度偏低", "内含额度分级标题")
    assertEqual(includedRun.alerts.first?.threshold ?? -1, 4, "内含额度阈值 4")

    // 无重置时间：文案不带「重置」
    let noReset = BillingBalance(percentLimits: [
        BillingPercentLimit(id: "weekly", title: "每周", remainingFraction: 0.01, resetsAt: nil),
    ])
    let noResetRun = BillingAlertEvaluator.evaluate(balance: noReset, providerID: "ollama", state: [:])
    assertEqual(noResetRun.alerts.first?.bodyText.contains("重置") ?? true, false, "无周期时正文不带重置")
    assertEqual(noResetRun.alerts.first?.bodyText ?? "", "剩余 1%", "无周期正文")
    assertEqual(noResetRun.alerts.first?.title(providerName: "Ollama") ?? "",
                "Ollama · 每周额度即将用尽", "1% 为即将用尽")

    // 多个 provider 互不影响
    let otherProvider = BillingAlertEvaluator.evaluate(balance: makeBalance(session: 0.04, weekly: 0.012),
                                                       providerID: "openai",
                                                       state: first.state)
    assertEqual(otherProvider.alerts.count, 2, "不同 provider 独立提醒")
    assertEqual(otherProvider.state["openai.session"]?.notifiedThreshold ?? -1, 4, "provider 键隔离")
}
