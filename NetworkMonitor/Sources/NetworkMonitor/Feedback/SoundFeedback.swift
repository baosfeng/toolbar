import AppKit
import NetworkMonitorCore

// MARK: - 操作音效

/// 操作音效 — 给剪贴板动作加一层听觉反馈
///
/// 口径（设计规格 §3 B3）：
/// - 只取系统自带音效，不引入任何音频资源；
/// - 默认关闭，设置页「操作音效」开关打开后才响；
/// - 同一 cue 200ms 内去重，避免连按刷音；
/// - 系统音取不到时静默跳过（不 beep 兜底），只留一条 debug 日志。
///
/// 开关放在 ClipboardPreferences，本类每次调用现读，设置页改完立即生效、无需回调。
@MainActor
final class SoundFeedback {

    /// 音效场景（剪贴板的五类主要动作）
    enum Cue: String, CaseIterable, Sendable {
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

        /// 对应的系统音名（NSSound(named:) 取值，不含扩展名）
        var systemSoundName: String {
            switch self {
            case .copy:   return "Tink"
            case .paste:  return "Pop"
            case .pin:    return "Glass"
            case .delete: return "Bottle"
            case .error:  return "Basso"
            }
        }
    }

    /// 同一 cue 的去重窗口（秒）
    private static let dedupeWindow: TimeInterval = 0.2

    private let preferences: ClipboardPreferences
    private let logger: LoggingService
    /// 每个 cue 上次实际播放的单调时钟（用系统运行时长，改动系统时间不影响去重）
    private var lastPlayed: [Cue: TimeInterval] = [:]

    init(preferences: ClipboardPreferences,
         logger: LoggingService = AppContext.shared.logger) {
        self.preferences = preferences
        self.logger = logger
    }

    /// 播放一个 cue（开关关闭 / 去重命中 / 系统音缺失时静默返回）
    func play(_ cue: Cue) {
        guard preferences.soundEffectsEnabled else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if let last = lastPlayed[cue], now - last < Self.dedupeWindow { return }
        lastPlayed[cue] = now
        guard let sound = NSSound(named: cue.systemSoundName) else {
            logger.debug("操作音效缺失：\(cue.systemSoundName)（cue=\(cue.rawValue)）")
            return
        }
        sound.play()
    }
}
