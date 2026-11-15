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
    /// 额度恢复（兜底）
    case billingRecovered = "billingWindowReset"
    /// 额度回升（兜底）
    case billingRecovery

    /// 归属事件（决定读哪一行的配置）
    public var event: NotificationEvent {
        switch self {
        case .copy, .paste, .pin, .delete, .error: return .clipboardAction
        case .panelToggle: return .panelToggle
        case .snipCapture: return .snipCaptured
        case .transferFinished: return .transferFinished
        case .billingAlert: return .billingAlert
        case .billingRecovered: return .billingRecovered
        case .billingRecovery: return .billingRecovery
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
        // 恢复与回升是好消息，用轻快的 Glass；额度跌破才用低沉的 Basso
        case .billingRecovered: return "Glass"
        case .billingRecovery: return "Glass"
        }
    }

    /// 「内建（咔哒）」档下按 cue 合成的性格族
    ///
    /// 复制与截图都是「做完一件事」的机械咔嚓，粘贴与面板开合都是「落下」的钝嗒，
    /// 收藏 / 传输完成 / 额度好消息用清亮的双击，删除是收走的唰，失败与告警才低沉。
    public var builtInFamily: CueSoundFamily {
        switch self {
        case .copy, .snipCapture: return .crisp
        case .paste, .panelToggle: return .thud
        case .pin, .transferFinished, .billingRecovered, .billingRecovery: return .chime
        case .delete: return .swipe
        case .error, .billingAlert: return .alert
        }
    }
}
