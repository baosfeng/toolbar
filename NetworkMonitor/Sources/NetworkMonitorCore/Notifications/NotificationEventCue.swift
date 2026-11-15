import Foundation

// MARK: - 事件对应的 cue

/// 事件 → 应用内 cue — 设置页「试听」与通知服务兜底共用的唯一映射
///
/// 剪贴板事件覆盖五个 cue（复制 / 粘贴 / 收藏 / 删除 / 失败），
/// 用户只配一行声音，试听时听到的必须是「复制」那一下：
/// 它是这五个里最常触发、也最能代表这一行性格的一个。
public extension NotificationEvent {

    /// 本事件试听 / 兜底时用的 cue（每个事件都有，不留可选）
    var previewCue: NotificationCue {
        switch self {
        case .billingAlert: return .billingAlert
        case .billingWindowReset: return .billingWindowReset
        case .billingRecovery: return .billingRecovery
        case .transferFinished: return .transferFinished
        case .snipCaptured: return .snipCapture
        case .clipboardAction: return .copy
        case .panelToggle: return .panelToggle
        }
    }
}
