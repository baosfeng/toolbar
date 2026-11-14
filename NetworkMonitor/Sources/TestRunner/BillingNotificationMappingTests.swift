import Foundation
import NetworkMonitorCore

// MARK: - 额度三类通知 → 事件表映射

/// 证明「阈值跌破 / 窗口重置 / 余额回升」三类额度通知各自落到事件表的一行，
/// 且这个映射不是口头约定：先用真实评估器产出三类 alert，再逐条走映射函数断言落点。
func runBillingNotificationMappingTests() {
    print("\n🧪 Testing 额度三类通知 → 事件表映射...")
    testBillingKindEventTable()
    testEvaluatorKindsMapToRows()
    testBillingRowsAreIndependent()
    print("✅ 额度三类通知 → 事件表映射 works")
}

/// 映射表本身：种类 → 事件行 → 兜底 cue，三个落点互不相同
private func testBillingKindEventTable() {
    let cases: [(BillingAlertKind, NotificationEvent)] = [
        (.threshold(3), .billingAlert),
        (.windowReset, .billingWindowReset),
        (.balanceRecovered, .billingRecovery),
    ]
    for (kind, expected) in cases {
        assertEqual(NotificationEvent.forBillingKind(kind), expected,
                    "\(kind) 落到事件行 \(expected.rawValue)")
        // cue 与事件的归属必须自洽：兜底音读的正是这一行的声音配置
        let cue = NotificationCue.forBillingKind(kind)
        assertEqual(cue.event, expected, "\(kind) 的兜底 cue 归属同一行")
        assertEqual(expected.postsSystemNotification, true,
                    "\(expected.rawValue) 是系统通知行（有提醒方式可配）")
        assertEqual(expected.defaultEnabled, true, "\(expected.rawValue) 默认开")
    }
    let rows: Set<NotificationEvent> = [.billingAlert, .billingWindowReset, .billingRecovery]
    assertEqual(rows.count, 3, "三类各自一行，不合并")
    assertEqual(NotificationEvent.billingAlert.label, "额度提醒", "阈值的行名")
    assertEqual(NotificationEvent.billingWindowReset.label, "额度重置", "重置的行名")
    assertEqual(NotificationEvent.billingRecovery.label, "额度回升", "回升的行名")
}

/// 端到端：真实评估器产出的三类 alert，逐条映射到事件行并打出映射表
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
    // BillingAlertKind 只有 Equatable（主分支没给 Hashable）：用「种类名 → 行」的有序表记录
    var observed = [(kind: String, event: NotificationEvent)]()
    func record(_ result: (alerts: [BillingAlert], state: [String: BillingAlertState]),
                label: String) {
        for alert in result.alerts {
            let event = NotificationEvent.forBillingKind(alert.kind)
            observed.append((describe(alert.kind), event))
            print("   \(label)：\(describe(alert.kind)) → \(event.rawValue)（\(event.label)）")
        }
    }

    // 1) 阈值跌破：首次观测 3%
    let first = BillingAlertEvaluator.evaluate(balance: balance(session: 0.03, resetsAt: base),
                                               providerID: "p", state: [:])
    record(first, label: "阈值跌破")
    assertEqual(row(for: "threshold(3)", in: observed), .billingAlert, "阈值跌破 → 额度提醒")

    // 2) 窗口重置：重置时刻往后走一个周期
    let nextCycle = base.addingTimeInterval(604_800)
    let reset = BillingAlertEvaluator.evaluate(balance: balance(session: 0.9, resetsAt: nextCycle),
                                               providerID: "p", state: first.state,
                                               now: base.addingTimeInterval(604_800))
    record(reset, label: "窗口重置")
    assertEqual(row(for: "windowReset", in: observed), .billingWindowReset, "窗口重置 → 额度重置")

    // 3) 余额回升：同一窗口内剩余从 30% 抬到 55%（+25 个百分点，超过默认 10）
    let low = BillingAlertEvaluator.evaluate(balance: balance(session: 0.30, resetsAt: nextCycle),
                                             providerID: "p", state: reset.state,
                                             now: base.addingTimeInterval(605_000))
    let up = BillingAlertEvaluator.evaluate(balance: balance(session: 0.55, resetsAt: nextCycle),
                                            providerID: "p", state: low.state,
                                            now: base.addingTimeInterval(606_000))
    record(up, label: "余额回升")
    assertEqual(row(for: "balanceRecovered", in: observed), .billingRecovery, "余额回升 → 额度回升")

    // 三类都在本轮真实出现过，映射表无缺口
    assertEqual(observed.count, 3, "本轮三类通知都出现过")
    let mappedRows = Set(observed.map(\.event))
    assertEqual(mappedRows, [.billingAlert, .billingWindowReset, .billingRecovery],
                "三类分别落到三行，无串行")
}

/// 三行的配置互相独立：改阈值那行的声音，不影响重置 / 回升两行
private func testBillingRowsAreIndependent() {
    let preferences = NotificationPreferences(storage: InMemoryStorage())
    preferences.setSound(.systemSound("Ping"), for: .billingAlert)
    preferences.setPresentation(.bannerOnly, for: .billingAlert)
    preferences.setEnabled(false, for: .billingWindowReset)
    assertEqual(preferences.config(for: .billingWindowReset).sound, .systemDefault,
                "重置行声音不受阈值行影响")
    assertEqual(preferences.config(for: .billingWindowReset).enabled, false, "重置行可单独关")
    assertEqual(preferences.config(for: .billingRecovery).presentation, .bannerAndSound,
                "回升行提醒方式不受阈值行影响")
}

/// 按种类名查映射结果（自证输出用）
private func row(for kind: String,
                 in observed: [(kind: String, event: NotificationEvent)]) -> NotificationEvent? {
    observed.first { $0.kind == kind }?.event
}

/// 种类可读描述（自证输出用）
private func describe(_ kind: BillingAlertKind) -> String {
    switch kind {
    case .threshold(let value): return "threshold(\(value))"
    case .windowReset: return "windowReset"
    case .balanceRecovered: return "balanceRecovered"
    }
}