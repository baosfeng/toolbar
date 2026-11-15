import Foundation
import NetworkMonitorCore

// MARK: - 额度恢复：判定 / 回升 / 偏好 / 向后兼容

/// 恢复通知的唯一门槛是「本周期用尽过」（用尽与静默两个场景见 BillingExhaustionTests）；
/// 这里钉住纯判定、余额回升、开关与老状态 JSON 的兼容。
func runBillingRecoveryTests() {
    print("\n🧪 Testing BillingRecoveryRule（纯判定）...")
    testRecoveryRule()

    print("\n🧪 Testing 余额回升通知...")
    testBalanceRecoveredNotification()

    print("\n🧪 Testing 恢复通知开关与偏好...")
    testRecoveryPreferences()

    print("\n🧪 Testing 场景 D：提醒状态向后兼容（旧 JSON）...")
    testAlertStateBackwardCompatibility()

    print("✅ Billing 恢复通知 works")
}

// MARK: - 跨文件共用夹具

/// 夹具（internal：BillingExhaustionTests 复用，TestRunner 是单模块）
let recoverySessionWindowA = BillingQuotaWindow(kind: .session, duration: 18_000,
                                                resetsAt: Date(timeIntervalSince1970: 1_800_000_000))
let recoverySessionWindowB = BillingQuotaWindow(kind: .session, duration: 18_000,
                                                resetsAt: Date(timeIntervalSince1970: 1_800_018_000))
let recoverySessionWindowC = BillingQuotaWindow(kind: .session, duration: 18_000,
                                                resetsAt: Date(timeIntervalSince1970: 1_800_036_000))

/// 会话窗口余额（window 为 nil 时等价于「provider 未声明窗口」）
func recoveryBalance(remaining: Double, window: BillingQuotaWindow?) -> BillingBalance {
    BillingBalance(percentLimits: [
        BillingPercentLimit(id: "session", title: "会话", remainingFraction: remaining,
                            resetsAt: window?.resetsAt, window: window),
    ])
}

/// 以 codex 为 providerID 评估一次
func recoveryEvaluate(_ balance: BillingBalance, _ state: [String: BillingAlertState],
                      now: Date = Date(timeIntervalSince1970: 1_800_000_000),
                      options: BillingAlertOptions = BillingAlertOptions())
    -> (alerts: [BillingAlert], state: [String: BillingAlertState]) {
    BillingAlertEvaluator.evaluate(balance: balance, providerID: "codex", state: state,
                                   now: now, options: options)
}

// MARK: - 纯判定

private func testRecoveryRule() {
    assertEqual(BillingRecoveryRule.isWindowReset(previous: nil, current: recoverySessionWindowA), false,
                "首次观测不算重置")
    assertEqual(BillingRecoveryRule.isWindowReset(previous: recoverySessionWindowA,
                                                current: recoverySessionWindowA), false,
                "同一周期不算重置")
    assertEqual(BillingRecoveryRule.isWindowReset(previous: recoverySessionWindowB,
                                                current: recoverySessionWindowA), false,
                "重置时刻后退不算新周期（服务端修正数据）")
    assertEqual(BillingRecoveryRule.isWindowReset(previous: recoverySessionWindowA,
                                                current: recoverySessionWindowB), true,
                "重置时刻前进 = 新周期")
    assertEqual(BillingRecoveryRule.isWindowReset(previous: recoverySessionWindowA, current: nil), false,
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

    let now = Date(timeIntervalSince1970: 1_800_000_000)
    assertEqual(BillingRecoveryRule.isCooldownElapsed(lastNotifiedAt: nil, now: now, cooldown: 3_600), true,
                "从未提醒过 → 不在冷却")
    assertEqual(BillingRecoveryRule.isCooldownElapsed(lastNotifiedAt: now.addingTimeInterval(-600),
                                                      now: now, cooldown: 3_600), false,
                "冷却内不提醒")

    // 恢复门槛：老状态与「上上周期用尽」都不算
    assertEqual(BillingRecoveryRule.wasExhaustedInPreviousCycle(nil), false, "无状态不算用尽过")
    assertEqual(BillingRecoveryRule.wasExhaustedInPreviousCycle(BillingAlertState()), false,
                "没有用尽记录（老 JSON）不算用尽过")
    assertEqual(BillingRecoveryRule.wasExhaustedInPreviousCycle(
                    BillingAlertState(cycleID: "a", exhaustedCycleID: "a")), true,
                "本周期用尽过 → 可发恢复")
    assertEqual(BillingRecoveryRule.wasExhaustedInPreviousCycle(
                    BillingAlertState(cycleID: "b", exhaustedCycleID: "a")), false,
                "上上周期用尽过不算（周期已切换）")
}

// MARK: - 余额回升

private func testBalanceRecoveredNotification() {
    let base = Date(timeIntervalSince1970: 1_800_000_000)
    let first = recoveryEvaluate(recoveryBalance(remaining: 0.1, window: nil), [:], now: base)
    assertEqual(first.alerts.isEmpty, true, "基线观测不通知")

    let recovered = recoveryEvaluate(recoveryBalance(remaining: 0.25, window: nil), first.state,
                                     now: base.addingTimeInterval(600))
    assertEqual(recovered.alerts.count, 1, "回升达到阈值触发提醒")
    assertEqual(recovered.alerts[0].kind, .balanceRecovered, "提醒种类为余额回升")
    assertEqual(recovered.alerts[0].title(providerName: "Codex"), "Codex · 会话额度回升", "回升标题")
    assertEqual(recovered.alerts[0].bodyText, "剩余 10% → 25%（+15 个百分点）", "回升正文带前后对比")

    let drop = recoveryEvaluate(recoveryBalance(remaining: 0.1, window: nil), recovered.state,
                                now: base.addingTimeInterval(1_200))
    let again = recoveryEvaluate(recoveryBalance(remaining: 0.3, window: nil), drop.state,
                                 now: base.addingTimeInterval(1_800))
    assertEqual(again.alerts.isEmpty, true, "冷却期内不重复提醒回升")

    let drop2 = recoveryEvaluate(recoveryBalance(remaining: 0.1, window: nil), again.state,
                                 now: base.addingTimeInterval(4_000))
    let afterCooldown = recoveryEvaluate(recoveryBalance(remaining: 0.3, window: nil), drop2.state,
                                         now: base.addingTimeInterval(7_400))
    assertEqual(afterCooldown.alerts.count, 1, "冷却结束后可再次提醒")

    let smallBase = recoveryEvaluate(recoveryBalance(remaining: 0.2, window: nil), [:], now: base)
    let small = recoveryEvaluate(recoveryBalance(remaining: 0.25, window: nil), smallBase.state,
                                  now: base.addingTimeInterval(600))
    assertEqual(small.alerts.isEmpty, true, "回升未达阈值不提醒")

    let custom = recoveryEvaluate(recoveryBalance(remaining: 0.25, window: nil), smallBase.state,
                                  now: base.addingTimeInterval(600),
                                  options: BillingAlertOptions(recoveryMinimumPercent: 5))
    assertEqual(custom.alerts.count, 1, "自定义阈值 5 时 +5 也提醒")

    let off = recoveryEvaluate(recoveryBalance(remaining: 0.25, window: nil), first.state,
                               now: base.addingTimeInterval(600),
                               options: BillingAlertOptions(notifyRecovery: false))
    assertEqual(off.alerts.isEmpty, true, "关闭回升通知后不提醒")
}

// MARK: - 偏好

private func testRecoveryPreferences() {
    let storage = InMemoryStorage()
    let prefs = BillingAlertPreferences(storage: storage)
    assertEqual(prefs.isRecoveredNotificationEnabled, true, "恢复通知缺省开启")
    assertEqual(prefs.isRecoveryNotificationEnabled, true, "回升通知缺省开启")
    assertEqual(prefs.recoveryMinimumPercent, 10, "回升阈值缺省 10 个百分点")

    prefs.setRecoveryMinimumPercent(200)
    assertEqual(prefs.recoveryMinimumPercent, 50, "阈值上限 50")
    prefs.setRecoveryMinimumPercent(0)
    assertEqual(prefs.recoveryMinimumPercent, 1, "阈值下限 1")

    prefs.setRecoveredNotificationEnabled(false)
    prefs.setRecoveryNotificationEnabled(false)
    let options = prefs.options
    assertEqual(options.notifyRecovered, false, "options 反映恢复开关")
    assertEqual(options.notifyRecovery, false, "options 反映回升开关")
    assertEqual(options.recoveryMinimumPercent, 1, "options 带钳制后的阈值")
    assertEqual(prefs.isEnabled, true, "额度提醒开关不受恢复开关影响")

    // 绑定键不变：恢复开关仍写在 billing.alerts.reset.enabled（老配置零迁移）
    assertEqual(storage.object(forKey: "billing.alerts.reset.enabled") as? Bool, false,
                "恢复开关沿用旧键 billing.alerts.reset.enabled")
}

// MARK: - 向后兼容（场景 D）

private func testAlertStateBackwardCompatibility() {
    // 老版本只写了 cycleID + notifiedThreshold：必须能解码，新字段为 nil
    let legacy = """
    {"codex.session":{"cycleID":"1800000000","notifiedThreshold":4,
     "lastRemainingFraction":0.004,"lastResetNotifiedCycleID":"1800000000"}}
    """.data(using: .utf8)!
    guard let decoded = try? JSONDecoder().decode([String: BillingAlertState].self, from: legacy) else {
        assertEqual("解码失败", "解码成功", "旧状态 JSON 可解码")
        return
    }
    assertEqual(decoded["codex.session"]?.notifiedThreshold ?? -1, 4, "旧字段保留")
    assertEqual(decoded["codex.session"]?.cycleID ?? "", "1800000000", "旧周期标识保留")
    assertEqual(decoded["codex.session"]?.lastWindow == nil, true, "缺失的窗口字段为 nil")
    assertEqual(decoded["codex.session"]?.exhaustedCycleID == nil, true, "缺失的用尽字段为 nil")

    // 老状态升级后第一轮：切周期也不许凭空发「已恢复」
    var legacyState = decoded
    legacyState["codex.session"]?.lastWindow = recoverySessionWindowA
    let upgrade = recoveryEvaluate(recoveryBalance(remaining: 1.0, window: recoverySessionWindowB),
                                   legacyState)
    assertEqual(upgrade.alerts.isEmpty, true, "老状态升级后不补发恢复通知")
    assertEqual(upgrade.state["codex.session"]?.exhaustedCycleID == nil, true, "也不会凭空记用尽")

    // 新状态编码 → 解码往返
    var state = decoded
    state["codex.session"]?.lastRemainingFraction = 0.42
    state["codex.session"]?.lastWindow = recoverySessionWindowA
    state["codex.session"]?.exhaustedCycleID = "session@1800000000"
    guard let data = try? JSONEncoder().encode(state),
          let roundTrip = try? JSONDecoder().decode([String: BillingAlertState].self, from: data) else {
        assertEqual("往返失败", "往返成功", "新状态往返")
        return
    }
    assertEqual(roundTrip["codex.session"]?.lastWindow?.cycleID ?? "",
                recoverySessionWindowA.cycleID, "窗口往返一致")
    assertEqual(roundTrip["codex.session"]?.lastRemainingFraction ?? 0, 0.42, "剩余基线往返一致")
    assertEqual(roundTrip["codex.session"]?.exhaustedCycleID ?? "", "session@1800000000",
                "用尽周期往返一致")
}
