import Foundation

// MARK: - 授权状态

/// 系统通知授权状态（设置页状态点 + 文案的唯一来源）
public enum NotificationAuthorizationState: String, Sendable, Equatable {
    /// 还没问过用户（首次启动、或系统还没弹过授权框）
    case notDetermined
    /// 用户拒绝（或系统策略不允许）
    case denied
    /// 已授权
    case authorized

    /// 状态文案
    public var label: String {
        switch self {
        case .notDetermined: return "未授权"
        case .denied: return "已关闭"
        case .authorized: return "已授权"
        }
    }

    /// 一句话说明（告诉用户下一步能做什么）
    public var detail: String {
        switch self {
        case .notDetermined: return "发送系统通知前需要你在弹窗里点「允许」"
        case .denied: return "系统设置 › 通知 › NetworkMonitor 里可以重新打开"
        case .authorized: return "系统通知可正常送达"
        }
    }
}

// MARK: - 通知内容

/// 一条待发送的通知 — 事件 + 标题 + 正文
///
/// 声音与提醒方式不在这里：它们由事件对应的偏好决定（NotificationPreferences），
/// 调用方只负责「发生了什么」，不负责「怎么提醒」。
public struct NotificationMessage: Equatable, Sendable {
    /// 事件（决定声音 / 提醒方式 / 开关）
    public let event: NotificationEvent
    /// 标题
    public let title: String
    /// 正文
    public let body: String

    public init(event: NotificationEvent, title: String, body: String) {
        self.event = event
        self.title = title
        self.body = body
    }
}

// MARK: - 通知服务

/// 系统通知入口协议 — 应用内所有系统通知的唯一出口
///
/// 实现拆分到 App 层（NotificationCenterService，UNUserNotificationCenter 封装）：
/// Core 不依赖 UserNotifications，测试用空实现即可断言调用方行为。
@MainActor
public protocol NotificationServicing: AnyObject {

    /// 当前授权状态（未知时先给 notDetermined，refresh 后更新）
    var authorizationState: NotificationAuthorizationState { get }

    /// 授权状态变化回调（设置页据此刷新状态点）
    var onAuthorizationChanged: ((NotificationAuthorizationState) -> Void)? { get set }

    /// 请求授权（已授权 / 已拒绝时系统静默返回，重复调用安全）
    func requestAuthorization()

    /// 主动刷新一次授权状态（打开设置页 / 回到前台时调用）
    func refreshAuthorizationState()

    /// 发送一条通知（按事件偏好决定声音与提醒方式；事件关闭时静默跳过）
    func post(_ message: NotificationMessage)

    /// 把当前引用到的音效同步进 ~/Library/Sounds（改完设置后调用）
    func syncInstalledSounds()
}

// MARK: - 空实现

/// 空实现 — 测试与「通知未装配」的降级场合使用（全部静默）
@MainActor
public final class SilentNotificationService: NotificationServicing {
    public private(set) var authorizationState: NotificationAuthorizationState = .notDetermined
    public var onAuthorizationChanged: ((NotificationAuthorizationState) -> Void)?

    public init() {}

    public func requestAuthorization() {}
    public func refreshAuthorizationState() {}
    public func post(_ message: NotificationMessage) {}
    public func syncInstalledSounds() {}
}
