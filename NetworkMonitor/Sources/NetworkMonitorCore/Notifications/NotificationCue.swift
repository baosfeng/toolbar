import Foundation

// MARK: - 应用内 cue

/// 应用内提示音场景 — 剪贴板 / 截图 / 面板三个就地反馈点
///
/// 与 NotificationEvent 是「多对一」：clipboardAction 一个事件覆盖复制 / 粘贴 / 收藏 /
/// 删除 / 失败五个 cue。用户只配一次「剪贴板动作用什么声音」，五个 cue 保留各自经典系统音
/// 作为「跟随系统」档的实际取值（失败仍是 Basso，成功仍是 Tink），不逼用户配五遍。
public enum NotificationCue: String, CaseIterable, Sendable {
    /// 复制（写回剪贴板成功）
    case copy
    /// 粘贴（合成 ⌘V 交回目标 App）
    case paste
    /// 收藏 / 贴到屏幕
    case pin
    /// 删除条目
    case delete
    /// 操作失败
    case error
    /// 面板弹出 / 收起
    case panelToggle
    /// 截图完成
    case snipCapture
    /// 传输完成（系统通知发不出去时的应用内兜底）
    case transferFinished
    /// 额度提醒（同上兜底；系统通知已授权时不会重复响）
    case billingAlert

    /// 归属事件（决定读哪一行的配置）
    public var event: NotificationEvent {
        switch self {
        case .copy, .paste, .pin, .delete, .error: return .clipboardAction
        case .panelToggle: return .panelToggle
        case .snipCapture: return .snipCaptured
        case .transferFinished: return .transferFinished
        case .billingAlert: return .billingAlert
        }
    }

    /// 「跟随系统」档下实际播放的系统音名（/System/Library/Sounds 文件名，无扩展名）
    public var defaultSystemSound: String {
        switch self {
        case .copy: return "Tink"
        case .paste: return "Pop"
        case .pin: return "Glass"
        case .delete: return "Bottle"
        case .error: return "Basso"
        case .panelToggle: return "Pop"
        case .snipCapture: return "Glass"
        case .transferFinished: return "Glass"
        case .billingAlert: return "Basso"
        }
    }
}
