import AppKit

// MARK: - 剪贴板动作反馈出口

/// 剪贴板音效出口 — 视图与控制器只依赖协议，实现是组合根装配的 SoundFeedback
///
/// 每次调用现读偏好（由实现保证），开关改完立即生效，这里不做任何缓存。
@MainActor
protocol ClipboardSoundPerforming: AnyObject {
    /// 播放一个音效场景
    func play(_ cue: SoundFeedback.Cue)
}

/// 剪贴板触觉出口 — 同上
@MainActor
protocol ClipboardHapticPerforming: AnyObject {
    /// 触发一次触觉反馈
    func tap(_ kind: HapticFeedback.Kind)
}

extension SoundFeedback: ClipboardSoundPerforming {}
extension HapticFeedback: ClipboardHapticPerforming {}

// MARK: - 成对注入载体

/// 剪贴板反馈成对出口 — 音效与触觉一起注入，调用方不必各持两个可选依赖
///
/// 由组合根在装配剪贴板链路时构造（见 AppCoordinator+Feedback），
/// 面板控制器与面板视图都只拿这一个值，不各自去取单例。
@MainActor
struct ClipboardFeedback {
    /// 音效出口
    let sound: any ClipboardSoundPerforming
    /// 触觉出口
    let haptics: any ClipboardHapticPerforming

    /// 空实现：面板在设置窗 / 快照等无反馈装配的场合使用（全部静默）
    static let silent = ClipboardFeedback(sound: SilentSoundFeedback(), haptics: SilentHapticFeedback())
}

// MARK: - 静默实现

/// 静默音效（无反馈装配时的占位）
@MainActor
private final class SilentSoundFeedback: ClipboardSoundPerforming {
    func play(_ cue: SoundFeedback.Cue) {}
}

/// 静默触觉（同上）
@MainActor
private final class SilentHapticFeedback: ClipboardHapticPerforming {
    func tap(_ kind: HapticFeedback.Kind) {}
}
