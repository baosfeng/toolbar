import Foundation
import NetworkMonitorCore

// MARK: - 额度恢复通知（窗口重置 / 余额回升）

/// 用户明确要求「周额度重置 / 恢复要能通知」，这里逐条钉住判定与文案：
/// 首次观测不算重置、同一周期只通知一次、回升要过阈值、冷却期内不重复、
/// 关掉开关后不产生对应提醒。
func runBillingRecoveryTests() {
    print("\n🧪 Testing BillingRecoveryRule（纯判定）...")
    testRecoveryRule()

    print("\n🧪 Testing 窗口重置通知...")
    testWindowResetNotification()

    print("\n🧪 Testing 余额回升通知...")
    testBalanceRecoveredNotification()

    print("\n🧪 Testing 恢复通知开关与偏好...")
    testRecoveryPreferences()

    print("\n🧪 Testing 提醒状态向后兼容（旧 JSON）...")
    testAlertStateBackwardCompatibility()

    print("✅ Billing 恢复通知 works")
}

// MARK: - 窗口与余额构造

private let sessionWindowA = BillingQuotaWindow(kind: .session, duration: 18_000,
                                                resetsAt: Date(timeIntervalSince1970: 1_800_000_000))
private let sessionWindowB = BillingQuotaWindow(kind: .session, duration: 18_000,
                                                resetsAt: Date(timeIntervalSince1970: 1_800_018_000))
private let weeklyWindowA = BillingQuotaWindow(kind: .weekly, duration: 604_800,
                                               resetsAt: Date(timeIntervalSince1970: 1_800_200_000))

private func sessionBalance(remaining: Double,
                            _ window: BillingQuotaWindow?) -> BillingBalance {
    BillingBalance(percentLimits: [
        BillingPercentLimit(id: "session", title: "会话", remainingFraction: remaining,
                            resetsAt: window?.resetsAt, window: window),
    ])
}

private func weeklyBalance(remaining: Double,
                           _ window: BillingQuotaWindow?) -> BillingBalance {
    BillingBalance(percentLimits: [
        BillingPercentLimit(id: "weekly", title: "每周", remainingFraction: remaining,
                            resetsAt: window?.resetsAt, window: window),
    ])
}

private func evaluate(_ balance: BillingBalance, _ state: [String: BillingAlertState],
                      now: Date = Date(timeIntervalSince1970: 1_800_000_000),
                      options: BillingAlertOptions = BillingAlertOptions())
    -> (alerts: [BillingAlert], state: [String: BillingAlertState]) {
    BillingAlertEvaluator.evaluate(balance: balance, providerID: "codex", state: state,
                                   now: now, options: options)
}

// MARK: - 纯判定

private func testRecoveryRule() {
    assertEqual(BillingRecoveryRule.isWindowReset(previous: nil, current: sessionWindowA), false,
                "首次观测不算重置")
    assertEqual(BillingRecoveryRule.isWindowReset(previous: sessionWindowA, current: sessionWindowA), false,
                "同一周期不算重置")
    assertEqual(BillingRecoveryRule.isWindowReset(previous: sessionWindowB, current: sessionWindowA), false,
                "重置时刻后退不算新周期（服务端修正数据）")
    assertEqual(BillingRecoveryRule.isWindowReset(previous: sessionWindowA, current: sessionWindowB), true,
                "重置时刻前进 = 新周期")
    assertEqual(BillingRecoveryRule.isWindowReset(previous: sessionWindowA, current: nil), false,
                "窗口消失不算重置")

    assertEqual(BillingRecoveryRule.recoveredPercent(from: nil, to: 0.5), 0, "无基线不判回升")
    assertEqual(BillingRecoveryRule.recoveredPercent(from: 0.1, to: 0.25), 15, "回升百分点")
    assertEqual(BillingRecoveryRule.recoveredPercent(from: 0.5, to: 0.2), 0, "下降不算回升")

    assertEqual(BillingRecoveryRule.shouldNotifyRecovery(recoveredPercent: 9.9, minimumPercent: 10), false,
                "未到阈值不提醒")
    assertEqual(BillingRecoveryRule.shouldNotifyRecovery(recoveredPercent: 10, minimumPercent: 10), true,
                "刚好到阈值即提醒")
    assertEqual(BillingRecoveryRule.shouldNotifyRecovery(recoveredPercent: 50, minimumPercent: 0), false,
                "阈值非正时不提醒（防御）")

    assertEqual(BillingRecoveryRule.isCooldownElapsed(lastNotifiedAt: nil, now: Date(), cooldown: 3_600), true,
                "从未提醒过 → 不在冷却")
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    assertEqual(BillingRecoveryRule.isCooldownElapsed(lastNotifiedAt: now.addingTimeInterval(-600),
                                                      now: now, cooldown: 3_600), false,
                "冷却内不提醒")
    assertEqual(BillingRecoveryRule.isCooldownElapsed(lastNotifiedAt: now.addingTimeInterval(-3_600),
                                                      now: now, cooldown: 3_600), true,
                "冷却结束可再提醒")
}

// MARK: - 窗口重置

private func testWindowResetNotification() {
    // 1) 首次观测：只记基线，不通知
    let first = evaluate(sessionBalance(remaining: 0.1, sessionWindowA), [:])
    assertEqual(first.alerts.isEmpty, true, "首次观测不通知")
    assertEqual(first.state["codex.session"]?.lastRemainingFraction ?? 0, 0.1, "首次观测写入剩余基线")
    assertEqual(first.state["codex.session"]?.lastWindow?.kind ?? .custom, .session, "首次观测写入窗口基线")

    // 2) 进入新周期（剩余回到 100%）：发一条「会话额度已重置」
    let reset = evaluate(sessionBalance(remaining: 1.0, sessionWindowB), first.state)
    assertEqual(reset.alerts.count, 1, "新周期只发一条（不再叠加回升提醒）")
    let alert = reset.alerts[0]
    assertEqual(alert.kind, .windowReset, "提醒种类为窗口重置")
    assertEqual(alert.title(providerName: "Codex"), "Codex · 5 小时额度已重置", "重置标题带窗口名（按窗口时长）")
    assertEqual(alert.bodyText.contains("已恢复至 100%"), true, "重置正文写明当前剩余")
    assertEqual(reset.state["codex.session"]?.notifiedThreshold ?? -1, 0, "重置把已提醒阈值归零")

    // 3) 同一周期重复观测：不重复通知
    let sameCycle = evaluate(sessionBalance(remaining: 0.95, sessionWindowB), reset.state)
    assertEqual(sameCycle.alerts.isEmpty, true, "同一周期不重复通知重置")

    // 4) 重置后再跌破：阈值提醒照常（归零后的新周期）
    let afterReset = evaluate(sessionBalance(remaining: 0.03, sessionWindowB), sameCycle.state)
    assertEqual(afterReset.alerts.count, 1, "新周期内跌破阈值可提醒")
    assertEqual(afterReset.alerts.first?.kind ?? .windowReset, .threshold(3), "跌破 3% 命中阈值 3")

    // 5) 周窗口重置（用户要的「周额度重置」）：文案用「每周」
    let weeklyFirst = evaluate(weeklyBalance(remaining: 0.2, weeklyWindowA), [:])
    assertEqual(weeklyFirst.alerts.isEmpty, true, "周窗口首次观测不通知")
    let weeklyReset = evaluate(weeklyBalance(remaining: 1.0,
                                             BillingQuotaWindow(kind: .weekly, duration: 604_800,
                                                                resetsAt: weeklyWindowA.resetsAt
                                                                    .addingTimeInterval(604_800))),
                               weeklyFirst.state)
    assertEqual(weeklyReset.alerts.count, 1, "周额度重置发一条")
    assertEqual(weeklyReset.alerts.first?.title(providerName: "Codex") ?? "",
                "Codex · 每周额度已重置", "周额度重置标题")

    // 6) 关闭重置通知：不产生重置提醒
    let silent = evaluate(sessionBalance(remaining: 1.0, sessionWindowB), first.state,
                          options: BillingAlertOptions(notifyWindowReset: false))
    assertEqual(silent.alerts.isEmpty, true, "关闭重置通知后不提醒")
}

// MARK: - 余额回升

private func testBalanceRecoveredNotification() {
    let base = Date(timeIntervalSince1970: 1_800_000_000)
    let first = evaluate(sessionBalance(remaining: 0.1, nil), [:], now: base)
    assertEqual(first.alerts.isEmpty, true, "基线观测不通知")

    // 回升 15 个百分点（阈值 10）→ 提醒
    let recovered = evaluate(sessionBalance(remaining: 0.25, nil), first.state,
                             now: base.addingTimeInterval(600))
    assertEqual(recovered.alerts.count, 1, "回升达到阈值触发提醒")
    let alert = recovered.alerts[0]
    assertEqual(alert.kind, .balanceRecovered, "提醒种类为余额回升")
    // 无窗口信息时按额度行标题兜底（这里 percentLimit.title = "会话"）
    assertEqual(alert.title(providerName: "Codex"), "Codex · 会话额度已恢复", "回升标题")
    assertEqual(alert.recoveredPercent ?? 0, 15, "回升百分比")
    assertEqual(alert.bodyText, "剩余 10% → 25%（+15 个百分点）", "回升正文带前后对比")

    // 冷却内再次回升：不提醒
    let drop = evaluate(sessionBalance(remaining: 0.1, nil), recovered.state,
                        now: base.addingTimeInterval(1_200))
    let again = evaluate(sessionBalance(remaining: 0.3, nil), drop.state,
                         now: base.addingTimeInterval(1_800))
    assertEqual(again.alerts.isEmpty, true, "冷却期内不重复提醒回升")

    // 冷却结束后再回升：提醒
    let drop2 = evaluate(sessionBalance(remaining: 0.1, nil), again.state,
                         now: base.addingTimeInterval(4_000))
    let afterCooldown = evaluate(sessionBalance(remaining: 0.3, nil), drop2.state,
                                 now: base.addingTimeInterval(7_400))
    assertEqual(afterCooldown.alerts.count, 1, "冷却结束后可再次提醒")

    // 回升不足阈值（+5 < 10）：不提醒
    let smallBase = evaluate(sessionBalance(remaining: 0.2, nil), [:], now: base)
    let small = evaluate(sessionBalance(remaining: 0.25, nil), smallBase.state,
                         now: base.addingTimeInterval(600))
    assertEqual(small.alerts.isEmpty, true, "回升未达阈值不提醒")

    // 自定义阈值 5：+5 就提醒
    let custom = evaluate(sessionBalance(remaining: 0.25, nil), smallBase.state,
                          now: base.addingTimeInterval(600),
                          options: BillingAlertOptions(recoveryMinimumPercent: 5))
    assertEqual(custom.alerts.count, 1, "自定义阈值 5 时 +5 也提醒")

    // 关闭回升通知：不提醒
    let off = evaluate(sessionBalance(remaining: 0.25, nil), first.state,
                       now: base.addingTimeInterval(600),
                       options: BillingAlertOptions(notifyRecovery: false))
    assertEqual(off.alerts.isEmpty, true, "关闭回升通知后不提醒")
}

// MARK: - 偏好

private func testRecoveryPreferences() {
    let storage = InMemoryStorage()
    let prefs = BillingAlertPreferences(storage: storage)
    assertEqual(prefs.isResetNotificationEnabled, true, "重置通知缺省开启")
    assertEqual(prefs.isRecoveryNotificationEnabled, true, "回升通知缺省开启")
    assertEqual(prefs.recoveryMinimumPercent, 10, "回升阈值缺省 10 个百分点")

    prefs.setRecoveryMinimumPercent(200)
    assertEqual(prefs.recoveryMinimumPercent, 50, "阈值上限 50")
    prefs.setRecoveryMinimumPercent(0)
    assertEqual(prefs.recoveryMinimumPercent, 1, "阈值下限 1")

    prefs.setResetNotificationEnabled(false)
    prefs.setRecoveryNotificationEnabled(false)
    let options = prefs.options
    assertEqual(options.notifyWindowReset, false, "options 反映重置开关")
    assertEqual(options.notifyRecovery, false, "options 反映回升开关")
    assertEqual(options.recoveryMinimumPercent, 1, "options 带钳制后的阈值")
    assertEqual(prefs.isEnabled, true, "阈值提醒开关不受恢复开关影响")
}

// MARK: - 向后兼容

private func testAlertStateBackwardCompatibility() {
    // 旧版本只写了 cycleID + notifiedThreshold：必须能解码，新字段为 nil
    let legacy = """
    {"ollama.session":{"cycleID":"2026-11-14T15:00:00Z","notifiedThreshold":4}}
    """.data(using: .utf8)!
    guard let decoded = try? JSONDecoder().decode([String: BillingAlertState].self, from: legacy) else {
        assertEqual("解码失败", "解码成功", "旧状态 JSON 可解码")
        return
    }
    assertEqual(decoded["ollama.session"]?.notifiedThreshold ?? -1, 4, "旧字段保留")
    assertEqual(decoded["ollama.session"]?.cycleID ?? "", "2026-11-14T15:00:00Z", "旧周期标识保留")
    assertEqual(decoded["ollama.session"]?.lastRemainingFraction == nil, true, "缺失的新字段为 nil")
    assertEqual(decoded["ollama.session"]?.lastWindow == nil, true, "缺失的窗口字段为 nil")

    // 新状态编码 → 解码往返
    var state = decoded
    state["ollama.session"]?.lastRemainingFraction = 0.42
    state["ollama.session"]?.lastWindow = sessionWindowA
    guard let data = try? JSONEncoder().encode(state),
          let roundTrip = try? JSONDecoder().decode([String: BillingAlertState].self, from: data) else {
        assertEqual("往返失败", "往返成功", "新状态往返")
        return
    }
    assertEqual(roundTrip["ollama.session"]?.lastWindow?.cycleID ?? "", sessionWindowA.cycleID, "窗口往返一致")
    assertEqual(roundTrip["ollama.session"]?.lastRemainingFraction ?? 0, 0.42, "剩余基线往返一致")
}
