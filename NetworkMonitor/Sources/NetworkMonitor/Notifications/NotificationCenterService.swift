import AppKit
import Foundation
import NetworkMonitorCore
import UserNotifications

// MARK: - 系统通知中心服务

/// 系统通知中心服务 — 应用内所有 UNUserNotificationCenter 调用的唯一出口
///
/// 收敛原因：额度提醒与传输通知各自持有一个 UNUserNotificationCenter 并发各自
/// 请求授权、各写一份 sound，改一处声音就得改两处；现在两条链路都只调 post(message:)，
/// 声音与提醒方式统一由事件偏好决定。
///
/// 提醒方式的实现（UNNotificationPresentationOptions，系统允许的组合）：
/// - 前台：由 willPresent 回调返回 [.banner, .sound] / [.banner] / [.list]；
/// - 后台：UNNotificationContent.sound 决定是否有声，横幅由系统「通知样式」决定
///   （App 无法强制横幅样式——这是系统设置，界面里已如实标注）。
@MainActor
final class NotificationCenterService: NSObject, NotificationServicing {

    // 放宽为 nonisolated：willPresent 回调在非主线程，需要就地读偏好算展示选项
    nonisolated private let preferences: NotificationPreferences
    private let installer: NotificationSoundInstaller
    private let logger: LoggingService
    private let center: UNUserNotificationCenter
    /// 上次同步进 ~/Library/Sounds 的引用集（避免每次发通知都扫目录）
    private var installedNames: Set<String> = []

    private(set) var authorizationState: NotificationAuthorizationState = .notDetermined
    var onAuthorizationChanged: ((NotificationAuthorizationState) -> Void)?

    init(preferences: NotificationPreferences,
         installer: NotificationSoundInstaller,
         logger: LoggingService = AppContext.shared.logger,
         center: UNUserNotificationCenter = .current()) {
        self.preferences = preferences
        self.installer = installer
        self.logger = logger
        self.center = center
        super.init()
        center.delegate = self
        refreshAuthorizationState()
    }

    // MARK: - 授权

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.logger.warning("通知授权失败：\(error.localizedDescription)")
                }
                self.authorizationState = granted ? .authorized : .denied
                self.onAuthorizationChanged?(self.authorizationState)
                self.logger.info("通知授权结果：\(self.authorizationState.label)")
            }
        }
    }

    func refreshAuthorizationState() {
        center.getNotificationSettings { [weak self] settings in
            let state: NotificationAuthorizationState
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: state = .authorized
            case .denied: state = .denied
            case .notDetermined: state = .notDetermined
            @unknown default: state = .notDetermined
            }
            Task { @MainActor in
                guard let self else { return }
                self.authorizationState = state
                self.onAuthorizationChanged?(state)
            }
        }
    }

    // MARK: - 发送

    func post(_ message: NotificationMessage) {
        let config = preferences.config(for: message.event)
        guard config.enabled else {
            logger.debug("通知已关闭，跳过：\(message.event.rawValue)")
            return
        }
        ensureSoundsInstalled()
        let content = UNMutableNotificationContent()
        content.title = message.title
        content.body = message.body
        let plan = NotificationSoundResolver.notificationPlan(
            selection: config.sound,
            presentation: config.presentation,
            installedName: { [weak self] selection in self?.installer.installedName(for: selection) })
        // 副本没装上（音效刚被删 / 复制失败）时回落系统默认音：
        // 引用一个不存在的文件名，系统会静默不响，用户完全无从察觉
        let effectivePlan: NotificationSoundPlan
        if case .named(let name) = plan, !installedNames.contains(name) {
            logger.warning("通知音效副本缺失，回落系统默认音：\(name)")
            effectivePlan = .systemDefault
        } else {
            effectivePlan = plan
        }
        switch effectivePlan {
        case .systemDefault:
            content.sound = .default
        case .named(let name):
            content.sound = UNNotificationSound(named: UNNotificationSoundName(name))
        case .silent:
            content.sound = nil
        }
        // userInfo 带上事件与声音方案：DEBUG 自检与系统通知列表排查都靠它
        content.userInfo = ["event": message.event.rawValue, "soundPlan": Self.describe(effectivePlan)]
        let request = UNNotificationRequest(identifier: "\(message.event.rawValue)-\(UUID().uuidString)",
                                            content: content,
                                            trigger: nil)
        center.add(request) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.logger.warning("通知投递失败：\(error.localizedDescription)（事件=\(message.event.rawValue)）")
                } else {
                    self.logger.info("通知已投递：\(message.title)｜声音=\(Self.describe(effectivePlan))｜方式=\(config.presentation.label)")
                }
            }
        }
    }

    /// 把偏好里引用的音效同步进 ~/Library/Sounds（设置页改完与每次投递前都调，幂等）
    func syncInstalledSounds() {
        installedNames = Set(installer.sync(preferences: preferences))
    }

    // MARK: - 内部

    /// 只在引用集没同步过时扫一次目录（投递路径要尽量轻）
    private func ensureSoundsInstalled() {
        guard installedNames.isEmpty else { return }
        syncInstalledSounds()
    }

    /// 声音方案的可读描述（日志与自检共用）
    private static func describe(_ plan: NotificationSoundPlan) -> String {
        switch plan {
        case .systemDefault: return "system-default"
        case .named(let name): return "named:\(name)"
        case .silent: return "silent"
        }
    }
}

// MARK: - 前台展示

extension NotificationCenterService: UNUserNotificationCenterDelegate {

    /// App 在前台时由这里决定「横幅 / 声音 / 只进列表」
    ///
    /// 后台投递时系统不看这个回调，声音由 content.sound 决定、横幅样式由系统设置决定
    /// （这两条边界在设置页文案里已如实标注）。
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let raw = notification.request.content.userInfo["event"] as? String
        let event = raw.flatMap { NotificationEvent(rawValue: $0) }
        // 就地算完就回调：completionHandler 不可逃逸到别的隔离域（Swift 6 会报 data race）
        completionHandler(Self.options(for: event, preferences: preferences))
    }

    /// 事件 → 前台展示选项（事件未知时按「横幅 + 声音」处理，不吞通知）
    nonisolated static func options(for event: NotificationEvent?,
                                    preferences: NotificationPreferences) -> UNNotificationPresentationOptions {
        guard let event else { return [.banner, .sound] }
        switch preferences.config(for: event).presentation {
        case .bannerAndSound: return [.banner, .sound]
        case .bannerOnly: return [.banner]
        case .notificationCenterOnly: return [.list]
        }
    }
}
