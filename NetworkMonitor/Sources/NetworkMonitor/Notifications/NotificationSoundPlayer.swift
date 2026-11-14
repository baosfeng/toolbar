import AppKit
import Foundation
import NetworkMonitorCore

// MARK: - 应用内音效播放

/// 应用内音效播放 — 事件配置 → 真实响的那一下
///
/// 口径：
/// - 每次调用现读偏好（NotificationPreferences）与音效目录，改完设置立即生效；
/// - 「跟随系统」按 cue 的经典系统音播（失败 Basso、成功 Tink……），
///   选具体系统音 / 自定义文件时全部 cue 用同一个声音；
/// - 静音与事件关闭都是「什么都不做」，不 beep 兜底；
/// - 同一 cue 200ms 内去重，连按不刷音；音量取通知页的「应用内音量」。
@MainActor
final class NotificationSoundPlayer {

    /// 同一 cue 的去重窗口（秒）
    private static let dedupeWindow: TimeInterval = 0.2

    private let preferences: NotificationPreferences
    private let library: NotificationSoundLibrary
    private let logger: LoggingService
    /// 每个 cue 上次实际播放的单调时钟（系统运行时长，改系统时间不影响去重）
    private var lastPlayed: [NotificationCue: TimeInterval] = [:]
    /// 正在播放的实例：NSSound 被释放就停播，必须强持有到播完
    private var playing: [NSSound] = []
    #if DEBUG
    /// 自证用：最近一次真正起播的声音名（系统音名或自定义文件名）
    private(set) var debugLastPlayedName = ""
    #endif

    init(preferences: NotificationPreferences,
         library: NotificationSoundLibrary,
         logger: LoggingService = AppContext.shared.logger) {
        self.preferences = preferences
        self.library = library
        self.logger = logger
    }

    /// 按 cue 所属事件的配置播放
    func play(_ cue: NotificationCue) {
        let config = preferences.config(for: cue.event)
        guard config.enabled else { return }
        guard passesDedupe(cue) else { return }
        play(selection: config.sound, cue: cue)
    }

    /// 用「指定事件」的配置播放一个 cue — 系统通知发不出去时的兜底
    ///
    /// 兜底必须读事件自己的配置（额度恢复读 billingRecovery 一行，而不是 billingAlert），
    /// 否则设置页里两行的声音分叉会在兜底路径上失效。
    func play(event: NotificationEvent, cue: NotificationCue) {
        let config = preferences.config(for: event)
        guard config.enabled else { return }
        guard passesDedupe(cue) else { return }
        play(selection: config.sound, cue: cue)
    }

    /// 试听（跳过开关与去重：设置页点「试听」必须立刻有声音，哪怕事件是关的）
    func preview(selection: NotificationSoundSelection, cue: NotificationCue) {
        play(selection: selection, cue: cue)
    }

    // MARK: - 内部

    /// 同一 cue 的去重判定（命中即记录本次时间）
    private func passesDedupe(_ cue: NotificationCue) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        if let last = lastPlayed[cue], now - last < Self.dedupeWindow { return false }
        lastPlayed[cue] = now
        return true
    }

    private func play(selection: NotificationSoundSelection, cue: NotificationCue) {
        guard let target = NotificationSoundResolver.cueSound(selection: selection, cue: cue) else {
            return
        }
        switch target {
        case .system(let name):
            guard let sound = NSSound(named: name) else {
                logger.debug("系统音效缺失：\(name)（cue=\(cue.rawValue)）")
                return
            }
            start(sound, debugName: "system:\(name)")
        case .customFile(let file):
            guard let url = library.url(forCustomFile: file), let sound = NSSound(contentsOf: url, byReference: true) else {
                logger.debug("自定义音效读取失败：\(file)（cue=\(cue.rawValue)）")
                return
            }
            start(sound, debugName: "custom:\(file)")
        }
    }

    /// 起播并强持有实例（最多保留 4 个，避免长时间运行堆积）
    private func start(_ sound: NSSound, debugName: String) {
        sound.volume = Float(preferences.inAppVolume)
        #if DEBUG
        // 记「解析出来的目标」而不是 sound.name：自定义文件用 NSSound(contentsOf:) 打开时 name 为 nil
        debugLastPlayedName = debugName
        #endif
        sound.play()
        playing.append(sound)
        if playing.count > 4 { playing.removeFirst(playing.count - 4) }
    }
}
