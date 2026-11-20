import NetworkMonitorCore

// MARK: - 音效出口端口

/// 音效播放出口 — 反馈层只依赖这个端口，真实播放器由 App 侧适配
///
/// 为什么要端口：真实播放器要碰 AppKit（NSSound）、音效库目录与偏好落盘，
/// 那是 App 组合根的事；反馈层只负责「cue 转发」，立端口后依赖方向仍是 App → Feature，
/// 不会成环，TestRunner 也不必拉起播放器就能断言转发路径。
@MainActor
public protocol FeedbackSoundPlaying: AnyObject {
    /// 播放一个 cue
    func play(_ cue: NotificationCue)
}

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
public final class SoundFeedback {

    /// 音效场景（剪贴板五个动作 + 面板 + 截图 + 两个系统通知事件的兜底）
    public typealias Cue = NotificationCue

    private let player: any FeedbackSoundPlaying

    public init(player: any FeedbackSoundPlaying) {
        self.player = player
    }

    /// 播放一个 cue（事件关闭 / 静音 / 音效缺失 / 去重命中时静默返回）
    public func play(_ cue: Cue) {
        player.play(cue)
    }
}
