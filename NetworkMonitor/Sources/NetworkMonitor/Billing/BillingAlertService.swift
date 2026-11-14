import AppKit
import NetworkMonitorCore

// MARK: - 额度提醒入口协议

/// 额度提醒入口 — BillingMonitor 只依赖此协议，通知实现可替换（测试用空实现）
@MainActor
protocol BillingAlerting: AnyObject {
    /// 余额刷新成功后调用：按阈值发系统通知并记录已提醒状态
    func handle(balance: BillingBalance, providerID: String, providerName: String)
}

// MARK: - 额度提醒实现

/// 额度阈值提醒 — 把 Core 的评估结果发成系统通知，并把「已提醒阈值」持久化到偏好
///
/// 阈值 5%/4%/3%/2%/1%：每个额度资源（内含额度 / 会话 / 每周）独立记录，
/// 同一周期同一档只提醒一次；余额回升或周期重置后发一条「额度恢复」。
///
/// 通知走统一的 NotificationCenterService（声音 / 提醒方式由设置页事件表决定）；
/// 系统通知未授权时退化为应用内提示音，避免用户「什么都没收到」。
@MainActor
final class BillingAlertService: BillingAlerting {

    /// 状态存储键（JSON：[String: BillingAlertState]）
    static let storageKey = "billing.alert.state"

    private let storage: any KeyValueStorage
    private let logger: LoggingService
    private let notifications: any NotificationServicing
    private let soundPlayer: NotificationSoundPlayer
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(storage: any KeyValueStorage = AppContext.shared.storage,
         notifications: any NotificationServicing,
         soundPlayer: NotificationSoundPlayer,
         logger: LoggingService = AppContext.shared.logger) {
        self.storage = storage
        self.notifications = notifications
        self.soundPlayer = soundPlayer
        self.logger = logger
    }

    /// 请求通知权限（App 启动时调用一次；已授权/已拒绝时系统静默返回）
    func requestAuthorizationIfNeeded() {
        notifications.requestAuthorization()
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
        for alert in result.alerts {
            send(event: .billingAlert,
                 title: alert.title(providerName: providerName),
                 body: alert.bodyText)
        }
        for recovery in result.recoveries {
            send(event: .billingRecovery,
                 title: recovery.title(providerName: providerName),
                 body: recovery.bodyText)
        }
        let summaries = result.alerts.map { "\($0.title(providerName: providerName)) \($0.bodyText)" }
            + result.recoveries.map { "\($0.title(providerName: providerName)) \($0.bodyText)" }
        if !summaries.isEmpty {
            logger.info("额度提醒已发送：\(summaries.joined(separator: "；"))")
        }
    }

    // MARK: - 发送

    /// 发一条额度相关通知；系统通知未授权时改为应用内提示音
    private func send(event: NotificationEvent, title: String, body: String) {
        if notifications.authorizationState == .authorized {
            notifications.post(NotificationMessage(event: event, title: title, body: body))
        } else {
            // 未授权时系统会静默丢弃通知，这里用应用内提示音兜住「有事情发生」这件事
            soundPlayer.play(event: event, cue: .billingAlert)
            logger.info("系统通知未授权，改为应用内提示音：\(title)")
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
