import AppKit
import NetworkMonitorCore
import UserNotifications

// MARK: - 额度提醒入口协议

/// 额度提醒入口 — `BillingMonitor` 只依赖此协议，通知实现可替换（测试用空实现）
@MainActor
protocol BillingAlerting: AnyObject {
    /// 余额刷新成功后调用：按阈值发系统通知并记录已提醒状态
    func handle(balance: BillingBalance, providerID: String, providerName: String)
}

// MARK: - 系统通知实现

/// 额度阈值提醒 — 把 Core 的评估结果发成系统通知，并把「已提醒阈值」持久化到偏好
///
/// 阈值 5%/4%/3%/2%/1%：每个额度资源（内含额度 / 会话 / 每周）独立记录，
/// 同一周期同一档只提醒一次；余额回升或周期重置后可再次提醒。
@MainActor
final class BillingAlertService: BillingAlerting {

    /// 状态存储键（JSON：`[String: BillingAlertState]`）
    static let storageKey = "billing.alert.state"

    private let storage: any KeyValueStorage
    private let logger: LoggingService
    private let center = UNUserNotificationCenter.current()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(storage: any KeyValueStorage = AppContext.shared.storage,
         logger: LoggingService = AppContext.shared.logger) {
        self.storage = storage
        self.logger = logger
    }

    /// 请求通知权限（App 启动时调用一次；已授权/已拒绝时系统静默返回）
    func requestAuthorizationIfNeeded() {
        center.requestAuthorization(options: [.alert, .sound]) { [logger] granted, error in
            if let error {
                logger.warning("额度提醒授权失败：\(error.localizedDescription)")
            } else if !granted {
                logger.info("额度提醒未授权（可在系统设置中开启）")
            }
        }
    }

    // MARK: - 处理

    func handle(balance: BillingBalance, providerID: String, providerName: String) {
        let oldState = loadState()
        let result = BillingAlertEvaluator.evaluate(balance: balance,
                                                    providerID: providerID,
                                                    state: oldState)
        // 状态有变化（含周期重置 / 回升清空）时落盘，即使本次没发提醒
        if result.state != oldState {
            saveState(result.state)
        }
        guard !result.alerts.isEmpty else { return }
        for alert in result.alerts {
            post(title: alert.title(providerName: providerName), body: alert.bodyText)
        }
        logger.info("额度提醒已发送：\(result.alerts.map { "\($0.title(providerName: providerName)) \($0.bodyText)" }.joined(separator: "；"))")
    }

    // MARK: - 通知

    private func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content,
                                            trigger: nil)
        center.add(request) { [logger] error in
            if let error {
                logger.warning("额度提醒发送失败：\(error.localizedDescription)")
            }
        }
    }

    // MARK: - 状态持久化

    private func loadState() -> [String: BillingAlertState] {
        guard let data = storage.object(forKey: Self.storageKey) as? Data else { return [:] }
        return (try? decoder.decode([String: BillingAlertState].self, from: data)) ?? [:]
    }

    private func saveState(_ state: [String: BillingAlertState]) {
        guard let data = try? encoder.encode(state) else { return }
        storage.set(data, forKey: Self.storageKey)
    }
}
