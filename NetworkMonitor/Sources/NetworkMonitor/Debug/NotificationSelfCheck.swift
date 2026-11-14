#if DEBUG
import AppKit
import AVFoundation
import NetworkMonitorCore
import UserNotifications

// MARK: - 通知与音效自检（仅 DEBUG）

/// 通知与音效自检 — NM_NOTIFY_SELFCHECK=/path/to/out.txt 时跑一遍并落盘证据
///
/// 检查三件事（正是需求里要求「给证据」的三条）：
/// 1. 偏好 → 应用内提示音：换自定义音效后，真正起播的目标必须从系统音变成自定义文件；
/// 2. 偏好 → 系统通知：每个事件算出 UNNotificationSound 的文件名，并核对它在 ~/Library/Sounds 里存在；
/// 3. 授权状态与真实投递：把投递结果与通知中心里的条目（含 userInfo 里的声音方案）一并记下来。
///
/// 实现口径：全程主线程 + RunLoop 自旋等待，不用逃逸闭包回调——
/// 逃逸闭包会把主线程状态（日志、偏好）拖进 @Sendable 捕获，为一支 DEBUG 探针招惹并发告警不值得。
/// 自检结束会还原偏好、删掉自测音效与通知中心条目，不留垃圾。
@MainActor
enum NotificationSelfCheck {

    /// 未设置环境变量时返回 nil
    static var requestedPath: String? {
        let path = ProcessInfo.processInfo.environment["NM_NOTIFY_SELFCHECK"] ?? ""
        return path.isEmpty ? nil : path
    }

    /// 入口：跑完写文件并退出（自检是取证用，不需要 App 继续运行）
    static func runIfRequested(coordinator: AppCoordinator) {
        guard let path = requestedPath else { return }
        let sink = LineSink(path: path)

        let preferences = coordinator.notificationPreferences!
        let library = coordinator.soundLibrary!
        let player = coordinator.soundPlayer!
        let service = coordinator.notificationService!

        service.refreshAuthorizationState()
        spin(seconds: 0.5)
        sink.emit("# 通知与音效自检 " + ISO8601DateFormatter().string(from: Date()))
        sink.emit("authorization=\(service.authorizationState.rawValue) detail=\(service.authorizationState.detail)")

        // MARK: 1. 事件表
        for event in NotificationEvent.allCases {
            let config = preferences.config(for: event)
            sink.emit("event.\(event.rawValue) enabled=\(config.enabled) sound=\(config.sound.storageValue) "
                      + "presentation=\(config.presentation.rawValue) haptic=\(config.haptic.rawValue) "
                      + "postsSystemNotification=\(event.postsSystemNotification)")
        }

        // MARK: 2. 应用内提示音：跟随系统 → 自定义
        let original = preferences.config(for: .clipboardAction)
        preferences.setEnabled(true, for: .clipboardAction)
        preferences.setSound(.systemDefault, for: .clipboardAction)
        player.play(.copy)
        sink.emit("inapp.before sound=\(original.sound.storageValue) played=\(player.debugLastPlayedName)")

        var importedFile: String?
        if let url = makeTestTone() {
            do {
                let file = try library.importSound(from: url)
                importedFile = file
                preferences.setSound(.customFile(file), for: .clipboardAction)
                // 同一 cue 有 200ms 去重窗口：这里是自证，必须等过窗口再放第二次，
                // 否则记录的还是上一条（会被误判成「设置没生效」）
                spin(seconds: 0.3)
                player.play(.copy)
                sink.emit("inapp.after sound=custom:\(file) played=\(player.debugLastPlayedName) "
                          + "storeBytes=\(library.store.totalBytes())")
                sink.emit("inapp.import.validated PASS file=\(file) aiff=\(file.hasSuffix(".aiff"))")
            } catch {
                sink.emit("inapp.import.validated FAIL error=\(error)")
            }
            try? FileManager.default.removeItem(at: url)
        }

        // MARK: 3. 系统通知音：把两类音都指到事件上，核对副本是否就位
        let originalRecoverySound = preferences.config(for: .billingRecovery).sound
        let originalAlertSound = preferences.config(for: .billingAlert).sound
        preferences.setSound(.systemSound("Glass"), for: .billingRecovery)
        if let importedFile {
            preferences.setSound(.customFile(importedFile), for: .billingAlert)
        }
        service.syncInstalledSounds()

        let soundsDir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Sounds")
        for event in NotificationEvent.allCases {
            let config = preferences.config(for: event)
            let plan = NotificationSoundResolver.notificationPlan(
                selection: config.sound,
                presentation: config.presentation,
                installedName: { selection in installedName(for: selection) })
            var exists = "n/a"
            if case .named(let name) = plan {
                exists = FileManager.default.fileExists(atPath: soundsDir.appendingPathComponent(name).path)
                    ? "present" : "missing"
            }
            sink.emit("notify.\(event.rawValue) plan=\(describe(plan)) copy=\(exists)")
        }
        let installed = (try? FileManager.default.contentsOfDirectory(atPath: soundsDir.path))?
            .filter { $0.hasPrefix(NotificationSoundInstaller.fileNamePrefix) } ?? []
        sink.emit("libsounds.copies=\(installed.sorted())")

        // MARK: 4. 真实投递
        service.requestAuthorization()
        spin(seconds: 1.0)
        service.refreshAuthorizationState()
        service.post(NotificationMessage(event: .billingAlert,
                                         title: "自检 · 额度提醒",
                                         body: "custom sound = \(preferences.config(for: .billingAlert).sound.storageValue)"))
        spin(seconds: 1.5)

        let box = DeliveredBox()
        UNUserNotificationCenter.current().getDeliveredNotifications { list in box.store(list) }
        spin(seconds: 2.0, until: { box.isLoaded })
        let delivered = box.items()
        sink.emit("deliver.authorization=\(service.authorizationState.rawValue) delivered=\(delivered.count)")
        for item in delivered.suffix(3) {
            let event = item.request.content.userInfo["event"] as? String ?? "?"
            let sound = item.request.content.userInfo["soundPlan"] as? String ?? "?"
            sink.emit("deliver.item id=\(item.request.identifier) event=\(event) "
                      + "soundPlan=\(sound) soundSet=\(item.request.content.sound != nil)")
        }
        // 自检发的是真通知：跑完把自己堆进通知中心的条目清掉，别把用户的通知中心当回收站
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()

        // MARK: 5. 收尾
        preferences.setSound(original.sound, for: .clipboardAction)
        preferences.setEnabled(original.enabled, for: .clipboardAction)
        preferences.setSound(originalRecoverySound, for: .billingRecovery)
        preferences.setSound(originalAlertSound, for: .billingAlert)
        if let importedFile { try? library.remove(importedFile) }
        service.syncInstalledSounds()
        sink.emit("cleanup.done importedRemoved=\(importedFile != nil)")
        exit(0)
    }

    // MARK: - 辅助

    /// 每次 sync 的副本命名与安装器一致（自检独立算一遍，避免依赖安装器实例）
    private static func installedName(for selection: NotificationSoundSelection) -> String? {
        let prefix = NotificationSoundInstaller.fileNamePrefix
        switch selection {
        case .systemSound(let name): return "\(prefix)sys-\(name).aiff"
        case .customFile(let file):
            let stem = (file as NSString).deletingPathExtension
            return "\(prefix)custom-\(stem).aiff"
        case .systemDefault, .silent: return nil
        }
    }

    /// 声音方案可读描述
    private static func describe(_ plan: NotificationSoundPlan) -> String {
        switch plan {
        case .systemDefault: return "system-default"
        case .named(let name): return "named:\(name)"
        case .silent: return "silent"
        }
    }

    /// 主线程自旋等待（可选提前结束条件）：自检要等异步回调落到可读状态
    private static func spin(seconds: TimeInterval, until done: (() -> Bool)? = nil) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if let done, done() { return }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
    }

    /// 生成一段 0.5 秒测试音（aiff）：走真实「上传 → 转码 → 落盘」链路，不依赖外部素材
    private static func makeTestTone() -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nm-selfcheck-tone.aiff")
        try? FileManager.default.removeItem(at: url)
        // 写必须在独立作用域内完成：AVAudioFile 析构时才 flush，句柄没关就读回来是空文件
        func write() {
            guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1),
                  let file = try? AVAudioFile(forWriting: url, settings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: 44_100,
                    AVNumberOfChannelsKey: 1,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: true,
                  ]) else { return }
            let frames = AVAudioFrameCount(22_050)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
            buffer.frameLength = frames
            if let data = buffer.floatChannelData?[0] {
                for index in 0..<Int(frames) {
                    data[index] = sinf(Float(index) * 2 * .pi * 660 / 44_100) * 0.25
                }
            }
            try? file.write(from: buffer)
        }
        write()
        return url
    }
}

// MARK: - 结果收集

/// 自检日志 — 每写一行就落盘（中途崩溃也能留下已得结论）
@MainActor
private final class LineSink {
    private let path: String
    private var lines: [String] = []

    init(path: String) { self.path = path }

    func emit(_ line: String) {
        lines.append(line)
        try? (lines.joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }
}

/// 已投递通知的收集盒 — 只捕获这个 Sendable 盒子，不把主线程状态拖进 @Sendable 闭包
private final class DeliveredBox: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [UNNotification]?

    var isLoaded: Bool {
        lock.lock(); defer { lock.unlock() }
        return list != nil
    }

    func store(_ notifications: [UNNotification]) {
        lock.lock(); list = notifications; lock.unlock()
    }

    func items() -> [UNNotification] {
        lock.lock(); defer { lock.unlock() }
        return list ?? []
    }
}
#endif
