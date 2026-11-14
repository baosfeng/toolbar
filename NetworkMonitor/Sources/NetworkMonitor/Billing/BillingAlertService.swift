import AppKit
import NetworkMonitorCore
import UserNotifications

// MARK: - 额度提醒入口协议

/// 额度提醒入口 — `BillingMonitor` 只依赖此协议，通知实现可替换（测试用空实现）
@MainActor
protocol BillingAlerting: AnyObject {
    /// 余额刷新成功后调用：按阈值 / 窗口重置 / 余额回升三类规则发系统通知并记录状态
    func handle(balance: BillingBalance, providerID: String, providerName: String)

    /// 删除实例时清掉该实例的提醒状态（键前缀 `<instanceID>.`）
    func clearAlerts(for providerID: String)
}

// MARK: - 系统通知实现

/// 额度提醒 — 把 Core 的评估结果发成系统通知，并把状态持久化到偏好
///
/// 三类通知（各自可在设置页关闭）：
/// - 阈值：5% / 4% / 3% / 2% / 1%，同一周期同一档只提醒一次；
/// - 窗口重置：会话 / 周 / 月额度进入新周期（同一 `cycleID` 只提醒一次）；
/// - 余额回升：相邻两次观测剩余回升达到阈值（默认 10 个百分点，带 1 小时冷却）。
@MainActor
final class BillingAlertService: BillingAlerting {

    /// 状态存储键（JSON：`[String: BillingAlertState]`）
    static let storageKey = "billing.alert.state"

    private let storage: any KeyValueStorage
    private let logger: LoggingService
    private let preferences: BillingAlertPreferences
    private let center = UNUserNotificationCenter.current()

    init(storage: any KeyValueStorage = AppContext.shared.storage,
         logger: LoggingService = AppContext.shared.logger,
         preferences: BillingAlertPreferences? = nil) {
        self.storage = storage
        self.logger = logger
        self.preferences = preferences ?? BillingAlertPreferences(storage: storage)
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
                                                    state: oldState,
                                                    now: Date(),
                                                    options: preferences.options)
        // 状态有变化（含周期重置 / 回升清空 / 基线刷新）时落盘，即使本次没发提醒
        if result.state != oldState {
            saveState(result.state)
        }
        guard !result.alerts.isEmpty else { return }
        for alert in result.alerts {
            post(title: alert.title(providerName: providerName), body: alert.bodyText)
        }
        logger.info("额度提醒已发送：\(result.alerts.map { "\($0.title(providerName: providerName)) \($0.bodyText)" }.joined(separator: "；"))")
    }

    /// 清除实例的提醒状态（删除实例时调用；同名新实例不会继承旧阈值记录）
    func clearAlerts(for providerID: String) {
        var state = loadState()
        let prefix = providerID + "."
        let keys = state.keys.filter { $0.hasPrefix(prefix) }
        guard !keys.isEmpty else { return }
        for key in keys { state.removeValue(forKey: key) }
        saveState(state)
        logger.info("已清除额度提醒状态 \(keys.count) 条（\(providerID)）")
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
        return (try? JSONDecoder().decode([String: BillingAlertState].self, from: data)) ?? [:]
    }

    private func saveState(_ state: [String: BillingAlertState]) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        storage.set(data, forKey: Self.storageKey)
    }
}
