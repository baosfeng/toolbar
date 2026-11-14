import AppKit
import NetworkMonitorCore
import UserNotifications

// MARK: - 额度提醒入口协议

/// 额度提醒入口 — BillingMonitor 只依赖此协议，通知实现可替换（测试用空实现）
@MainActor
protocol BillingAlerting: AnyObject {
    /// 余额刷新成功后调用：按阈值 / 窗口重置 / 余额回升三类规则发系统通知并记录状态
    func handle(balance: BillingBalance, providerID: String, providerName: String)

    /// 删除实例时清掉该实例的提醒状态（键前缀 `<instanceID>.`）
    func clearAlerts(for providerID: String)
}

// MARK: - 额度提醒实现

/// 额度提醒 — 把 Core 的评估结果发成系统通知，并把状态持久化到偏好
///
/// 三类通知（各自可在设置页关闭）：
/// - 阈值：5% / 4% / 3% / 2% / 1%，同一周期同一档只提醒一次；
/// - 窗口重置：会话 / 周 / 月额度进入新周期（同一 `cycleID` 只提醒一次）；
/// - 余额回升：相邻两次观测剩余回升达到阈值（默认 10 个百分点，带 1 小时冷却）。
///
/// 通知走统一的 NotificationCenterService（声音 / 提醒方式由设置页事件表决定），
/// 三类各自落到事件表的一行（见 `NotificationEvent.forBillingKind`）；
/// 系统通知未授权时退化为应用内提示音，避免用户「什么都没收到」。
///
/// 两层开关的分工（同时存在，语义不重叠）：
/// - 额度 Provider 页的「阈值 / 重置 / 回升」开关（`BillingAlertPreferences.options`）
///   决定**是否产生**这类提醒（连应用内提示音一起不产生）；
/// - 「通知与音效」页对应行的开关决定这条提醒**是否真的推送**（声音 / 提醒方式也在那一行）。
/// 任一层关掉都不打扰用户；两层都开才推送。
@MainActor
final class BillingAlertService: BillingAlerting {

    /// 状态存储键（JSON：[String: BillingAlertState]）
    static let storageKey = "billing.alert.state"

    private let storage: any KeyValueStorage
    private let logger: LoggingService
    private let notifications: any NotificationServicing
    private let soundPlayer: NotificationSoundPlayer
    private let preferences: BillingAlertPreferences
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(storage: any KeyValueStorage = AppContext.shared.storage,
         notifications: any NotificationServicing,
         soundPlayer: NotificationSoundPlayer,
         logger: LoggingService = AppContext.shared.logger,
         preferences: BillingAlertPreferences? = nil) {
        self.storage = storage
        self.notifications = notifications
        self.soundPlayer = soundPlayer
        self.logger = logger
        self.preferences = preferences ?? BillingAlertPreferences(storage: storage)
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
                                                    state: oldState,
                                                    now: Date(),
                                                    options: preferences.options)
        // 状态有变化（含周期重置 / 回升清空 / 基线刷新）时落盘，即使本次没发提醒
        if result.state != oldState {
            saveState(result.state)
        }
        guard !result.alerts.isEmpty else { return }
        for alert in result.alerts {
            send(kind: alert.kind,
                 title: alert.title(providerName: providerName),
                 body: alert.bodyText)
        }
        let summaries = result.alerts.map { "\($0.title(providerName: providerName)) \($0.bodyText)" }
        logger.info("额度提醒已发送：\(summaries.joined(separator: "；"))")
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

    // MARK: - 发送

    /// 发一条额度相关通知；系统通知未授权时改为应用内提示音
    ///
    /// 种类 → 事件表行由 Core 的纯函数决定（三类各自可配声音与提醒方式），
    /// 这里不再自己判断「这是不是恢复类通知」。
    private func send(kind: BillingAlertKind, title: String, body: String) {
        let event = NotificationEvent.forBillingKind(kind)
        if notifications.authorizationState == .authorized {
            notifications.post(NotificationMessage(event: event, title: title, body: body))
        } else {
            // 未授权时系统会静默丢弃通知，这里用应用内提示音兜住「有事情发生」这件事
            soundPlayer.play(event: event, cue: NotificationCue.forBillingKind(kind))
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
