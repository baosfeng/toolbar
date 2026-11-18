import Foundation
import NetworkMonitorCore

// MARK: - 恢复通知按窗口勾选

/// 用户口径：「有的是周额度和五小时额度，可以自定义恢复通知」。
/// 这里钉住四件事：只勾 weekly 时 session 不发、weekly 发；缺键全发；
/// `window == nil` 不受影响；非法 kind 值忽略不崩。
func runBillingRecoveredWindowTests() {
    print("\n🧪 Testing 恢复通知按窗口勾选（纯函数）...")
    testRecoveredWindowPolicyPure()
    testRecoveredWindowInvalidKind()

    print("\n🧪 Testing 恢复通知按窗口勾选（评估器）...")
    testRecoveredWindowEvaluator()
}

// MARK: - 纯函数

private func testRecoveredWindowPolicyPure() {
    assertEqual(BillingRecoveredWindowPolicy.unrestricted(providerID: "codex").allows(.session), true,
                "未配置窗口 → 全窗口通知")
    assertEqual(BillingRecoveredWindowPolicy.unrestricted(providerID: "codex").allows(nil), true,
                "未配置窗口 → 无窗口信息也通知")

    let weeklyOnly = BillingRecoveredWindowPolicy(providerID: "codex", enabledKinds: [.weekly])
    assertEqual(weeklyOnly.allows(.weekly), true, "勾了 weekly → weekly 通知")
    assertEqual(weeklyOnly.allows(.session), false, "只勾 weekly → session 不通知")
    assertEqual(weeklyOnly.allows(.daily), false, "只勾 weekly → daily 不通知")
    assertEqual(weeklyOnly.allows(nil), true, "window == nil 不受窗口勾选影响（余额型 provider 不被静默）")

    let none = BillingRecoveredWindowPolicy(providerID: "codex", enabledKinds: [])
    assertEqual(none.allows(.weekly), false, "全部不勾 → 窗口类额度不通知")
    assertEqual(none.allows(nil), true, "全部不勾也不影响无窗口信息额度")

    // 存储层
    let storage = InMemoryStorage()
    let prefs = BillingAlertPreferences(storage: storage)
    assertEqual(prefs.shouldNotifyRecovery(providerID: "codex", windowKind: .session), true,
                "缺键 → 回落既有行为（全窗口通知）")
    assertEqual(prefs.hasRecoveredWindowSelection(providerID: "codex"), false, "缺键不算做过窗口选择")

    prefs.setRecoveredWindowEnabled(true, providerID: "codex", windowKind: .weekly)
    prefs.setRecoveredWindowEnabled(false, providerID: "codex", windowKind: .session)
    assertEqual(prefs.shouldNotifyRecovery(providerID: "codex", windowKind: .weekly), true,
                "只勾 weekly → weekly 恢复通知")
    assertEqual(prefs.shouldNotifyRecovery(providerID: "codex", windowKind: .session), false,
                "只勾 weekly → session 恢复不发")
    assertEqual(prefs.shouldNotifyRecovery(providerID: "codex", windowKind: nil), true,
                "window == nil 一律不受影响")
    assertEqual(prefs.shouldNotifyRecovery(providerID: "ollama", windowKind: .session), true,
                "其他 provider 不受影响（键按实例隔离）")
    assertEqual(storage.object(forKey: "billing.alerts.recovered.codex.weekly") as? Bool, true,
                "键名 billing.alerts.recovered.<providerID>.<windowKind>")

    let options = prefs.options(for: "codex")
    assertEqual(options.recoveredWindows?.allows(.session) ?? true, false, "options(for:) 带上窗口策略")
    assertEqual(options.notifyRecovered, true, "恢复总开关仍由 isRecoveredNotificationEnabled 决定")

    prefs.removeRecoveredWindowSelection(providerID: "codex")
    assertEqual(prefs.hasRecoveredWindowSelection(providerID: "codex"), false, "删除实例后清掉窗口选择")
    assertEqual(prefs.shouldNotifyRecovery(providerID: "codex", windowKind: .session), true,
                "清掉窗口选择后回到「全窗口通知」")
}

// MARK: - 非法 kind

private func testRecoveredWindowInvalidKind() {
    let storage = InMemoryStorage()
    storage.set(false, forKey: "billing.alerts.recovered.codex.bogus")
    storage.set(true, forKey: "billing.alerts.recovered.codex.weekly")
    let prefs = BillingAlertPreferences(storage: storage)

    assertEqual(prefs.shouldNotifyRecovery(providerID: "codex", windowKind: .weekly), true,
                "非法 kind 键被忽略，合法键照常生效")
    assertEqual(prefs.shouldNotifyRecovery(providerID: "codex", windowKind: .session), true,
                "非法 kind 键不会让其他窗口被判成关闭")
    assertEqual(BillingWindowKind(rawValue: "bogus") == nil, true, "非法 rawValue 不构造出种类")
}

// MARK: - 评估器

private func testRecoveredWindowEvaluator() {
    let base = Date(timeIntervalSince1970: 1_800_000_000)
    func sessionWindow(_ offset: TimeInterval) -> BillingQuotaWindow {
        BillingQuotaWindow(kind: .session, duration: 18_000,
                           resetsAt: Date(timeIntervalSince1970: 1_800_000_000 + offset))
    }
    func weeklyWindow(_ offset: TimeInterval) -> BillingQuotaWindow {
        BillingQuotaWindow(kind: .weekly, duration: 604_800,
                           resetsAt: Date(timeIntervalSince1970: 1_800_000_000 + offset))
    }
    func balance(limitID: String, title: String, remaining: Double,
                 window: BillingQuotaWindow?) -> BillingBalance {
        BillingBalance(percentLimits: [
            BillingPercentLimit(id: limitID, title: title, remainingFraction: remaining,
                                resetsAt: window?.resetsAt, window: window),
        ])
    }
    func evaluate(_ balance: BillingBalance, _ state: [String: BillingAlertState],
                  options: BillingAlertOptions) -> (alerts: [BillingAlert], state: [String: BillingAlertState]) {
        BillingAlertEvaluator.evaluate(balance: balance, providerID: "codex", state: state,
                                       now: base, options: options)
    }

    // 只勾 weekly：session 用尽后切周期不发恢复，weekly 用尽后切周期发
    var sessionState: [String: BillingAlertState] = [:]
    let sessionOptions = BillingAlertOptions(
            recoveredWindows: BillingRecoveredWindowPolicy(providerID: "codex", enabledKinds: [.weekly]))
    let sessionFirst = evaluate(balance(limitID: "session", title: "会话", remaining: 0.004,
                                        window: sessionWindow(0)), sessionState, options: sessionOptions)
    assertEqual(sessionFirst.alerts.count, 1, "用尽仍要通知（窗口勾选只作用于恢复）")
    sessionState = sessionFirst.state
    let sessionRecovered = evaluate(balance(limitID: "session", title: "会话", remaining: 1,
                                            window: sessionWindow(18_000)),
                                    sessionState, options: sessionOptions)
    assertEqual(sessionRecovered.alerts.contains { $0.kind == .recovered }, false,
                "只勾 weekly → session 恢复不发")

    var weeklyState: [String: BillingAlertState] = [:]
    let weeklyFirst = evaluate(balance(limitID: "weekly", title: "每周", remaining: 0.004,
                                       window: weeklyWindow(0)), weeklyState, options: sessionOptions)
    assertEqual(weeklyFirst.alerts.count, 1, "weekly 用尽通知")
    weeklyState = weeklyFirst.state
    let weeklyRecovered = evaluate(balance(limitID: "weekly", title: "每周", remaining: 1,
                                           window: weeklyWindow(604_800)),
                                   weeklyState, options: sessionOptions)
    assertEqual(weeklyRecovered.alerts.contains { $0.kind == .recovered }, true,
                "只勾 weekly → weekly 恢复发")

    // 缺键 = 不设窗口策略：全部窗口都发
    let legacyOptions = BillingAlertOptions()
    var legacyState: [String: BillingAlertState] = [:]
    let legacyFirst = evaluate(balance(limitID: "session", title: "会话", remaining: 0.004,
                                       window: sessionWindow(0)), legacyState, options: legacyOptions)
    legacyState = legacyFirst.state
    let legacyRecovered = evaluate(balance(limitID: "session", title: "会话", remaining: 1,
                                           window: sessionWindow(18_000)),
                                   legacyState, options: legacyOptions)
    assertEqual(legacyRecovered.alerts.contains { $0.kind == .recovered }, true,
                "缺键时回落既有行为：全窗口都发恢复")

    // window == nil：纯余额型额度，勾选不影响
    let noneOptions = BillingAlertOptions(recoveredWindows: BillingRecoveredWindowPolicy(
                                            providerID: "deepseek", enabledKinds: []))
    var nilState: [String: BillingAlertState] = [:]
    let nilFirst = evaluate(balance(limitID: "credits", title: "余额", remaining: 0.004,
                                    window: nil), nilState, options: noneOptions)
    nilState = nilFirst.state
    let nilRecovered = evaluate(balance(limitID: "credits", title: "余额", remaining: 0.5,
                                        window: nil), nilState, options: noneOptions)
    assertEqual(nilRecovered.alerts.contains { $0.kind == .recovered }, true,
                "window == nil 的额度不受窗口勾选影响（不会被静默掉）")
}
