import AppKit
import NetworkMonitorCore

// MARK: - 操作音效

/// 操作音效 — 给剪贴板动作加一层听觉反馈
///
/// 口径（统一到「通知与音效」设置页的剪贴板动作一行）：
/// - 声音、开关、音量都来自 NotificationPreferences，本类不再自己持开关，
///   所以设置页改完立即生效（下一次调用就换声音）；
/// - 默认档是「内建（咔哒）」：按 cue 播合成的设计音（复制脆响、粘贴钝咔、删除下行……），
///   「跟随系统」档才回落到经典系统音（复制 Tink / 粘贴 Pop），选具体音效或自定义文件时五个 cue 统一；
/// - 默认为「关」（既有口径：操作音效默认关闭）。
@MainActor
final class SoundFeedback {

    /// 音效场景（剪贴板五个动作 + 面板 + 截图 + 两个系统通知事件的兜底）
    typealias Cue = NotificationCue

    private let player: NotificationSoundPlayer

    init(player: NotificationSoundPlayer) {
        self.player = player
    }

    /// 播放一个 cue（事件关闭 / 静音 / 音效缺失 / 去重命中时静默返回）
    func play(_ cue: Cue) {
        player.play(cue)
    }
}