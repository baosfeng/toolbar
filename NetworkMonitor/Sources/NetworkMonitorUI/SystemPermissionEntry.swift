import Foundation
import NetworkMonitorCore

// MARK: - 单条权限的展示口径

/// 一类权限在当前状态下的展示口径 —— 行名 / 文案 / 灯色 / 标签 / 按钮全在这里
///
/// 拆出 `SystemPermissionLogic.swift` 的原因：那个文件放「权限有哪些 / 状态有几种 /
/// 动作有哪几种」的枚举与基础文案，这里放「一类权限在某个状态下怎么显示」的派生规则。
public struct SystemPermissionEntry: Equatable, Sendable {

    /// 权限类别
    public let kind: SystemPermissionKind
    /// 当前状态
    public let state: SystemPermissionState
    /// 登录项注册失败的回滚说明（只有登录项会用到；nil = 没发生过回滚）
    public let rollbackReason: String?

    public init(kind: SystemPermissionKind,
                state: SystemPermissionState,
                rollbackReason: String? = nil) {
        self.kind = kind
        self.state = state
        self.rollbackReason = rollbackReason
    }

    /// 行名
    public var title: String { kind.title }
    /// 状态文案（登录项 / 通知按系统侧说法）
    public var label: String { kind.label(for: state) }
    /// 状态点语义
    public var tone: SettingsStatusTone { state.tone }
    /// 是否正处在「检测中」（视图据此画出等待态而不是「未授权」）
    public var isChecking: Bool { state == .checking }

    /// 行尾标签（需重启 / 无请求 API / 登录项）；nil = 不显示
    public var tag: String? {
        switch kind {
        case .screenCapture: return state.isGranted ? "需重启" : nil
        case .clipboard:     return "无请求 API"
        case .loginItem:     return "登录项"
        case .accessibility, .notification: return nil
        }
    }

    /// 行副标题：用途 + 当前处置办法
    public var detail: String {
        let purpose = kind.purpose
        switch state {
        case .granted:
            return kind.requiresRestartAfterGrant
                ? "\(purpose)：已授权，重启 \(AppIdentity.displayName) 后生效"
                : "\(purpose)：已生效，无需重启"
        case .pending:
            return kind.requiresRestartAfterGrant
                ? "\(purpose)：未开启，打开开关后需重启"
                : "\(purpose)：未开启，打开开关即生效"
        case .denied:
            return "\(purpose)：已关闭，需在系统设置里打开"
        case .unregistered:
            return rollbackReason == nil
                ? "\(purpose)：未登记"
                : "\(purpose)：系统未允许，已回滚为关"
        case .unknown:
            return "\(purpose)：当前系统读不到授权状态"
        case .checking:
            return purpose
        }
    }

    /// 主按钮（强调底）；nil = 这一行不需要动作
    public var primaryAction: SystemPermissionAction? {
        switch kind {
        case .accessibility:
            return state.isGranted ? nil : .grant
        case .screenCapture:
            return state.isGranted ? .restartApp : .grant
        case .clipboard:
            return state.isGranted ? nil : .openSettings
        case .notification:
            switch state {
            case .granted:  return nil
            case .pending:  return .grant
            case .checking, .unknown, .denied, .unregistered: return .openSettings
            }
        case .loginItem:
            return state.isGranted ? nil : .openLoginItems
        }
    }

    /// 次按钮（文字链）；nil = 不显示
    public var secondaryAction: SystemPermissionAction? {
        switch kind {
        case .accessibility, .screenCapture: return .revealInFinder
        case .clipboard, .notification, .loginItem: return nil
        }
    }

    /// 是否显示行内开关（只有登录项能从这里直接开关）
    public var showsLoginItemSwitch: Bool { kind == .loginItem }

    /// 是否显示卡下的重启提示 —— 屏幕录制已授权时恒显示
    public var showsRestartHint: Bool { kind.requiresRestartAfterGrant && state.isGranted }

    /// 是否显示「在系统设置列表里找到本应用」这条引导
    public var showsManualAddGuide: Bool { kind.supportsManualAdd && !state.isGranted }

    /// 功能页就地简版的状态文案（只表达「生效了没有」，不改主卡口径）
    public var inPlaceStateLabel: String { state.isGranted ? "已生效" : label }

    /// 在系统设置列表里找到本应用的引导
    ///
    /// - Parameter appPath: 应用包绝对路径（UI 库不碰 Bundle，由 App 层传入）
    public func manualAddGuide(appPath: String) -> String {
        let name = AppIdentity.displayName
        switch kind {
        case .screenCapture:
            return "在「录屏与系统录音」列表里找中文名「\(name)」并打开开关；"
                + "确实没有时点列表下方 + 添加 \(appPath)"
        case .accessibility:
            return "在「辅助功能」列表里找中文名「\(name)」并打开开关；"
                + "确实没有时点列表下方 + 添加 \(appPath)"
        case .clipboard, .notification, .loginItem:
            return ""
        }
    }

    /// 卡下的重启提示（不需要重启 / 未授权时为空串）
    public var restartHint: String {
        guard showsRestartHint else { return "" }
        return "\(kind.title)已授权：重启 \(AppIdentity.displayName) 后截图才能生效"
    }
}
