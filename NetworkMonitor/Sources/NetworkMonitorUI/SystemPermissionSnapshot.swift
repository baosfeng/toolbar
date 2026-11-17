import Foundation
import NetworkMonitorCore

// MARK: - 五类权限的合计快照

/// 五类权限的合计快照 —— UI 只读它，不各自调系统 API
///
/// 生成侧只有一个：`SystemPermissionCenter.refresh()`（同步三类 + 缓存的通知 + 登录项）。
public struct SystemPermissionSnapshot: Equatable, Sendable {

    public var accessibility: SystemPermissionState
    public var screenCapture: SystemPermissionState
    public var clipboard: SystemPermissionState
    public var notification: SystemPermissionState
    public var loginItem: SystemPermissionState
    /// 登录项注册失败的回滚说明（nil = 没发生过回滚）
    public var loginItemRollbackReason: String?

    public init(accessibility: SystemPermissionState,
                screenCapture: SystemPermissionState,
                clipboard: SystemPermissionState,
                notification: SystemPermissionState = .unknown,
                loginItem: SystemPermissionState = .unknown,
                loginItemRollbackReason: String? = nil) {
        self.accessibility = accessibility
        self.screenCapture = screenCapture
        self.clipboard = clipboard
        self.notification = notification
        self.loginItem = loginItem
        self.loginItemRollbackReason = loginItemRollbackReason
    }

    /// 尚未读取过任何一项（首帧与低版本系统的兜底）
    public static let allUnknown = SystemPermissionSnapshot(accessibility: .unknown,
                                                           screenCapture: .unknown,
                                                           clipboard: .unknown)

    /// 全部置为检测中（重读已发出、结果未到）
    public static let allChecking = SystemPermissionSnapshot(accessibility: .checking,
                                                             screenCapture: .checking,
                                                             clipboard: .checking,
                                                             notification: .checking,
                                                             loginItem: .checking)

    /// 取某一类的状态
    public func state(for kind: SystemPermissionKind) -> SystemPermissionState {
        switch kind {
        case .accessibility: return accessibility
        case .screenCapture:  return screenCapture
        case .clipboard:      return clipboard
        case .notification:   return notification
        case .loginItem:      return loginItem
        }
    }

    /// 取某一类的展示口径
    public func entry(for kind: SystemPermissionKind) -> SystemPermissionEntry {
        SystemPermissionEntry(kind: kind,
                              state: state(for: kind),
                              rollbackReason: kind == .loginItem ? loginItemRollbackReason : nil)
    }

    /// 五类按固定顺序展开（设置页按这个顺序建行）
    public var entries: [SystemPermissionEntry] {
        SystemPermissionKind.allCases.map(entry(for:))
    }

    /// 已授权的类数
    public var grantedCount: Int {
        SystemPermissionKind.allCases.filter { state(for: $0).isGranted }.count
    }

    /// 待处理的类数（待授权 / 已关闭 / 未登记；检测中与未知不算「待处理」）
    public var pendingCount: Int {
        SystemPermissionKind.allCases.filter {
            switch state(for: $0) {
            case .pending, .denied, .unregistered: return true
            case .granted, .unknown, .checking:    return false
            }
        }.count
    }

    /// 是否还有需要用户处理的权限（未知也算：先引导用户检测一次）
    public var needsAttention: Bool {
        SystemPermissionKind.allCases.contains { !state(for: $0).isGranted }
    }

    /// 页头胶囊主语：`权限 2/5 已授权`
    public var summaryLabel: String {
        "权限 \(grantedCount)/\(SystemPermissionKind.allCases.count) 已授权"
    }

    /// 页头胶囊灯色：全绿才算达标，有待处理就是告警，只剩未知 / 检测中用中性色
    public var summaryTone: SettingsStatusTone {
        if grantedCount == SystemPermissionKind.allCases.count { return .ok }
        return pendingCount > 0 ? .warn : .muted
    }

    /// 是否全部还在「检测中」（用于「异步结果没回来」的兜底判定）
    public var isAllChecking: Bool {
        SystemPermissionKind.allCases.allSatisfy { state(for: $0) == .checking }
    }
}

// MARK: - 系统读数 → 权限状态的归一

public extension SystemPermissionSnapshot {

    /// Core 的剪贴板五态 → 权限状态
    ///
    /// 归一口径：只有「已允许」是达标；「已拒绝」单列（用户明确关过）；
    /// 「每次询问 / 系统默认」是「还没授权」；低版本读不到访问行为是「未知」。
    static func clipboardState(from access: ClipboardAccessState) -> SystemPermissionState {
        switch access {
        case .allowed:            return .granted
        case .denied:             return .denied
        case .ask, .unspecified:  return .pending
        case .unknown:            return .unknown
        }
    }

    /// 通知授权三态 → 权限状态（未决定 / 已拒绝都还没授权，但文案不同）
    static func notificationState(from authorization: NotificationAuthorizationState) -> SystemPermissionState {
        switch authorization {
        case .authorized:    return .granted
        case .denied:        return .denied
        case .notDetermined: return .pending
        }
    }

    /// 登录项四档 → 权限状态（待批准是「差用户点一下」；未登记 / 未找到都是「未登记」）
    static func loginItemState(from registration: LaunchAtStartupRegistration) -> SystemPermissionState {
        switch registration {
        case .enabled:                  return .granted
        case .requiresApproval:         return .pending
        case .notRegistered, .notFound: return .unregistered
        }
    }
}
