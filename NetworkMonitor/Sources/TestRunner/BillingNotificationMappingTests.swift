import Foundation
import NetworkMonitorCore

// MARK: - 额度通知 → 事件表映射

/// 证明四类额度通知（用尽 / 偏低 / 恢复 / 回升）各自落到事件表的一行，
/// 且这个映射不是口头约定：先用真实评估器产出各类 alert，再逐条走映射函数断言落点。
func runBillingNotificationMappingTests() {
    print("\n🧪 Testing 额度通知 → 事件表映射...")
    testBillingKindEventTable()
    testEvaluatorKindsMapToRows()
    testBillingRowsAreIndependent()
    print("✅ 额度通知 → 事件表映射 works")
}

/// 映射表本身：种类 → 事件行 → 兜底 cue，落点互不相同（用尽与偏低共用提醒行）
private func testBillingKindEventTable() {
    let cases: [(BillingAlertKind, NotificationEvent)] = [
        (.exhausted, .billingAlert),
        (.threshold(3), .billingAlert),
        (.recovered, .billingRecovered),
        (.balanceRecovered, .billingRecovery),
    ]
    for (kind, expected) in cases {
        assertEqual(NotificationEvent.forBillingKind(kind), expected,
                    "\(describe(kind)) 落到事件行 \(expected.rawValue)")
        // cue 与事件的归属必须自洽：兜底音读的正是这一行的声音配置
        let cue = NotificationCue.forBillingKind(kind)
        assertEqual(cue.event, expected, "\(describe(kind)) 的兜底 cue 归属同一行")
        assertEqual(expected.postsSystemNotification, true,
                    "\(expected.rawValue) 是系统通知行（有提醒方式可配）")
        assertEqual(expected.defaultEnabled, true, "\(expected.rawValue) 默认开")
    }
    let rows: Set<NotificationEvent> = [.billingAlert, .billingRecovered, .billingRecovery]
    assertEqual(rows.count, 3, "三类事件行，用尽与偏低共用提醒行")
    assertEqual(NotificationEvent.billingAlert.label, "额度提醒", "提醒的行名")
    assertEqual(NotificationEvent.billingRecovered.label, "额度恢复", "恢复的行名")
    assertEqual(NotificationEvent.billingRecovery.label, "额度回升", "回升的行名")

    // 老偏好零迁移：恢复行的 rawValue 仍是 billingWindowReset，键名没变
    assertEqual(NotificationEvent.billingRecovered.rawValue, "billingWindowReset",
                "恢复行的 rawValue 保持旧值（老配置的键继续有效）")
    assertEqual(NotificationCue.billingRecovered.event, .billingRecovered, "cue 归属一致")
    assertEqual(NotificationCue.billingRecovered.rawValue, "billingWindowReset",
                "cue 的 rawValue 同样保持旧值")
}

/// 端到端：真实评估器产出的各类 alert，逐条映射到事件行并打出映射表
private func testEvaluatorKindsMapToRows() {
    let base = Date(timeIntervalSince1970: 1_800_000_000)
    func window(resetsAt: Date) -> BillingQuotaWindow {
        BillingQuotaWindow(kind: .weekly, duration: 604_800, resetsAt: resetsAt)
    }
    func balance(session: Double, resetsAt: Date) -> BillingBalance {
        BillingBalance(percentLimits: [
            BillingPercentLimit(id: "session", title: "会话",
                                remainingFraction: session, resetsAt: resetsAt,
                                window: window(resetsAt: resetsAt)),
        ])
    }
    // BillingAlertKind 只有 Equatable（没给 Hashable）：用「种类名 → 行」的有序表记录
    var observed = [(kind: String, event: NotificationEvent)]()
    func record(_ result: (alerts: [BillingAlert], state: [String: BillingAlertState]),
                label: String) {
        for alert in result.alerts {
            let event = NotificationEvent.forBillingKind(alert.kind)
            observed.append((describe(alert.kind), event))
            print("   \(label)：\(describe(alert.kind)) → \(event.rawValue)（\(event.label)）")
        }
    }

    // 1) 偏低预告：首次观测 3%
    let first = BillingAlertEvaluator.evaluate(balance: balance(session: 0.03, resetsAt: base),
                                               providerID: "p", state: [:])
    record(first, label: "偏低预告")
    assertEqual(row(for: "threshold(3)", in: observed), .billingAlert, "偏低预告 → 额度提醒")

    // 2) 用尽：跌破用尽线
    let drained = BillingAlertEvaluator.evaluate(balance: balance(session: 0.008, resetsAt: base),
                                                 providerID: "p", state: first.state,
                                                 now: base.addingTimeInterval(60))
    record(drained, label: "额度用尽")
    assertEqual(row(for: "exhausted", in: observed), .billingAlert, "用尽 → 额度提醒")

    // 3) 恢复：窗口切周期
    let nextCycle = base.addingTimeInterval(604_800)
    let reset = BillingAlertEvaluator.evaluate(balance: balance(session: 0.9, resetsAt: nextCycle),
                                               providerID: "p", state: drained.state,
                                               now: nextCycle)
    record(reset, label: "额度恢复")
    assertEqual(row(for: "recovered", in: observed), .billingRecovered, "恢复 → 额度恢复")

    // 4) 回升：同一窗口内剩余从 30% 抬到 55%（+25 个百分点，超过默认 10）
    let low = BillingAlertEvaluator.evaluate(balance: balance(session: 0.30, resetsAt: nextCycle),
                                             providerID: "p", state: reset.state,
                                             now: nextCycle.addingTimeInterval(500))
    let up = BillingAlertEvaluator.evaluate(balance: balance(session: 0.55, resetsAt: nextCycle),
                                            providerID: "p", state: low.state,
                                            now: nextCycle.addingTimeInterval(600))
    record(up, label: "余额回升")
    assertEqual(row(for: "balanceRecovered", in: observed), .billingRecovery, "回升 → 额度回升")

    // 四类都在本轮真实出现过，映射表无缺口
    let kinds = Set(observed.map(\.kind))
    assertEqual(kinds.count, 4, "本轮四类通知都出现过：\(kinds.sorted())")
    let mappedRows = Set(observed.map(\.event))
    assertEqual(mappedRows, [.billingAlert, .billingRecovered, .billingRecovery],
                "四类落到三行，用尽与偏低共用提醒行")
}

/// 三行的配置互相独立：改提醒那行的声音，不影响恢复 / 回升两行
private func testBillingRowsAreIndependent() {
    let preferences = NotificationPreferences(storage: InMemoryStorage())
    preferences.setSound(.systemSound("Ping"), for: .billingAlert)
    preferences.setPresentation(.bannerOnly, for: .billingAlert)
    preferences.setEnabled(false, for: .billingRecovered)
    assertEqual(preferences.config(for: .billingRecovered).sound, .systemDefault,
                "恢复行声音不受提醒行影响")
    assertEqual(preferences.config(for: .billingRecovered).enabled, false, "恢复行可单独关")
    assertEqual(preferences.config(for: .billingRecovery).presentation, .bannerAndSound,
                "回升行提醒方式不受提醒行影响")
    // 旧键继续生效：恢复行的开关仍写在 notify.billingWindowReset.enabled
    assertEqual(preferences.isEnabled(.billingRecovered), false, "旧键读到的关闭态生效")
    assertEqual(preferences.config(for: .billingRecovered).enabled, false, "读的就是这一行的配置")
}

/// 按种类名查映射结果（自证输出用）
private func row(for kind: String,
                 in observed: [(kind: String, event: NotificationEvent)]) -> NotificationEvent? {
    observed.first { $0.kind == kind }?.event
}

/// 种类可读描述（自证输出用）
private func describe(_ kind: BillingAlertKind) -> String {
    switch kind {
    case .exhausted: return "exhausted"
    case .threshold(let value): return "threshold(\(value))"
    case .recovered: return "recovered"
    case .balanceRecovered: return "balanceRecovered"
    }
}
