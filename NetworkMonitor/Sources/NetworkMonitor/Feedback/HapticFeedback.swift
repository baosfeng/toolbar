import AppKit
import NetworkMonitorCore

// MARK: - 触觉反馈

/// 触觉反馈 — 把面板交互映射到系统触控板反馈
///
/// 口径（统一到「通知与音效」设置页的剪贴板动作一行）：
/// - 档位来自 NotificationHaptic（关 / 轻 / 标准 / 有力），默认「标准」= 既有行为；
/// - macOS 只提供三种 FeedbackPattern，没有数值强度，档位即图案（见 NotificationHaptic 注释）；
/// - 无触控板时由系统自行忽略，不做设备探测；
/// - 触觉不受事件的「提示音开关」影响：音效关掉、触觉照样生效（这是既有口径，也是用户预期）。
@MainActor
final class HapticFeedback {

    /// 触发时机（保留语义分类；具体图案由设置里的档位决定）
    enum Kind: String, CaseIterable, Sendable {
        /// 卡片选中切换
        case selection
        /// 收藏切换（有「档位变化」的语义）
        case levelChange
        /// 其余确认类动作
        case generic

        /// 归属事件
        var event: NotificationEvent { .clipboardAction }
    }

    private let preferences: NotificationPreferences

    init(preferences: NotificationPreferences) {
        self.preferences = preferences
    }

    /// 触发一次反馈（档位关闭时直接返回）
    func tap(_ kind: Kind) {
        let level = preferences.config(for: kind.event).haptic
        guard level.isEnabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(Self.pattern(for: level),
                                                         performanceTime: .now)
    }

    /// 档位 → 系统图案
    static func pattern(for level: NotificationHaptic) -> NSHapticFeedbackManager.FeedbackPattern {
        switch level {
        case .light: return .alignment
        case .strong: return .levelChange
        case .standard, .off: return .generic
        }
    }
}
