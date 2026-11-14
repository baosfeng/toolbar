import AppKit

// MARK: - 触觉反馈

/// 触觉反馈 — 把面板交互映射到系统触控板反馈
///
/// 口径（设计规格 §3 B4）：默认开启；无触控板时由系统自行忽略，不做设备探测。
/// 开关放在 ClipboardPreferences，本类每次调用现读，设置页改完立即生效。
@MainActor
final class HapticFeedback {

    /// 触发时机
    enum Kind: String, CaseIterable, Sendable {
        /// 卡片选中切换
        case selection
        /// 收藏切换（有「档位变化」的语义）
        case levelChange
        /// 其余确认类动作
        case generic

        /// 系统反馈模式：selection 没有同名模式，「对齐」手感最接近
        var pattern: NSHapticFeedbackManager.FeedbackPattern {
            switch self {
            case .selection:   return .alignment
            case .levelChange: return .levelChange
            case .generic:     return .generic
            }
        }
    }

    private let preferences: ClipboardPreferences

    init(preferences: ClipboardPreferences) {
        self.preferences = preferences
    }

    /// 触发一次反馈（开关关闭时直接返回）
    func tap(_ kind: Kind) {
        guard preferences.hapticsEnabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(kind.pattern, performanceTime: .now)
    }
}
