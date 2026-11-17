import Foundation
import NetworkMonitorCore

// MARK: - 系统权限（纯逻辑）

/// 本应用需要的五类系统权限 —— 设置页、功能页就地入口与截图引导共用这一份口径
///
/// 抽到 UI 库的原因：状态 → 灯色 / 文案 / 标签 / 按钮 / 是否需要重启 都是纯规则，
/// TestRunner 能直接断言；App 层只保留系统 API 的读取与请求，以及深链的拼装。
/// 拆分：单条口径在 `SystemPermissionEntry`，合计快照在 `SystemPermissionSnapshot`，
/// 卡下说明在 `SystemPermissionNotes`。
public enum SystemPermissionKind: String, CaseIterable, Sendable {
    /// 辅助功能：全局 ⌘V 监听与合成粘贴
    case accessibility
    /// 屏幕录制：截图 / 取色 / 窗口检测
    case screenCapture
    /// 剪贴板访问：历史记录采集
    case clipboard
    /// 系统通知：事件推送（额度提醒、截图完成等）
    case notification
    /// 开机自启动：SMAppService 登录项
    case loginItem

    /// 行名（设置页、就地入口与日志共用）
    public var title: String {
        switch self {
        case .accessibility: return "辅助功能"
        case .screenCapture:  return "屏幕录制"
        case .clipboard:      return "剪贴板访问"
        case .notification:   return "系统通知"
        case .loginItem:      return "开机自启动"
        }
    }

    /// 本权限用在哪里（行副标题的固定半句）
    public var purpose: String {
        switch self {
        case .accessibility: return "Paste Stack 的 ⌘V 监听与自动粘贴"
        case .screenCapture:  return "截图、取色与窗口检测"
        case .clipboard:      return "剪贴板历史采集"
        case .notification:   return "额度提醒、截图完成等事件推送"
        case .loginItem:      return "登录后自动启动 \(AppIdentity.displayName)"
        }
    }

    /// 系统设置的锚点名 —— 全仓唯一出处
    ///
    /// 前三类是「隐私与安全性」面板里的子锚点，后两类是独立的设置扩展面板 id；
    /// 完整深链只在 App 层 `SystemPermissionCenter.openSettings(for:)` 拼一次。
    public var settingsAnchor: String {
        switch self {
        case .accessibility: return "Privacy_Accessibility"
        case .screenCapture:  return "Privacy_ScreenCapture"
        case .clipboard:      return "Privacy"
        case .notification:   return "com.apple.Notifications-Settings.extension"
        case .loginItem:      return "com.apple.LoginItems-Settings.extension"
        }
    }

    /// 锚点是接在「隐私与安全性」面板之后（true），还是独立面板 id（false）
    public var anchorsPrivacyPane: Bool {
        switch self {
        case .accessibility, .screenCapture, .clipboard: return true
        case .notification, .loginItem: return false
        }
    }

    /// 授权后是否必须重启应用才生效
    ///
    /// 屏幕录制不同：TCC 缓存的是进程启动时读到的授权，用户勾完必须重启本进程才拿得到屏幕内容；
    /// 辅助功能（AXIsProcessTrusted）、剪贴板访问、通知与登录项都是下一次读取即变。
    public var requiresRestartAfterGrant: Bool { self == .screenCapture }

    /// 是否需要给出「在系统设置列表里按中文名找到本应用」的引导
    ///
    /// 只有两类隐私面板是「按曾请求过的应用列出」的清单；剪贴板访问、通知与登录项没有这一层。
    public var supportsManualAdd: Bool {
        switch self {
        case .accessibility, .screenCapture: return true
        case .clipboard, .notification, .loginItem: return false
        }
    }

    /// 本类权限的状态文案 —— 默认走状态自身文案，登录项与通知用系统侧自己的说法
    public func label(for state: SystemPermissionState) -> String {
        switch (self, state) {
        case (.loginItem, .granted):      return "已登记"
        case (.loginItem, .pending):      return "待批准"
        case (.loginItem, .unregistered): return "未登记"
        case (.notification, .pending):   return "未授权"
        default:                          return state.label
        }
    }
}

// MARK: - 状态

/// 一类权限的判定结果 —— 六种，映射到三种灯色
///
/// 为什么不止三态：通知「已关闭」、登录项「未登记」（含注册失败回滚）与普通「待授权」
/// 对用户的处置不同，文案必须分得开；「检测中」是独立的中间态，
/// 让「重读还没回来」不会被显示成「未授权」。
public enum SystemPermissionState: String, CaseIterable, Sendable {
    /// 已授权（登录项为「已登记」）
    case granted
    /// 待授权（开关没开；通知为「未授权」，登录项为「待批准」）
    case pending
    /// 用户在系统里明确关掉了
    case denied
    /// 登录项未登记（含注册失败后回滚为关）
    case unregistered
    /// 读不到（系统版本不支持该读数，或本次尚未读取）
    case unknown
    /// 检测中（重读已发出、结果还没回来）
    case checking

    /// 状态文案（行内右侧的默认口径）
    public var label: String {
        switch self {
        case .granted:      return "已授权"
        case .pending:      return "待授权"
        case .denied:       return "已关闭"
        case .unregistered: return "未登记"
        case .unknown:      return "未知"
        case .checking:     return "检测中"
        }
    }

    /// 状态点语义（绿 / 黄 / 灰）
    public var tone: SettingsStatusTone {
        switch self {
        case .granted:                            return .ok
        case .pending, .denied:                   return .warn
        case .unregistered, .unknown, .checking:  return .muted
        }
    }

    /// 是否达标（只有「已授权 / 已登记」算达标）
    public var isGranted: Bool { self == .granted }
}

// MARK: - 动作

/// 权限行上的可执行动作 —— 标题与主次样式都在这里，视图只按它建按钮
public enum SystemPermissionAction: String, CaseIterable, Sendable {
    /// 请求授权（会登记进系统设置清单并弹一次系统提示）
    case grant
    /// 打开对应的系统设置面板
    case openSettings
    /// 去「登录项与扩展」面板
    case openLoginItems
    /// 在 Finder 中显示应用包（用户手动 + 添加时要自己找到 .app）
    case revealInFinder
    /// 重启应用（屏幕录制授权后 TCC 才重新读取）
    case restartApp

    /// 按钮标题
    public var title: String {
        switch self {
        case .grant:          return "授权"
        case .openSettings:   return "打开系统设置"
        case .openLoginItems: return "去登录项"
        case .revealInFinder: return "在 Finder 中显示"
        case .restartApp:     return "重启应用"
        }
    }

    /// 主按钮（强调底）还是文字链
    public var isPrimary: Bool {
        switch self {
        case .grant, .restartApp: return true
        case .openSettings, .openLoginItems, .revealInFinder: return false
        }
    }
}
