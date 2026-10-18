import AppKit
import NetworkMonitorCore
import UserNotifications

// MARK: - 传输通知与音效

/// 传输通知 — 完成 / 失败的系统通知与系统音效
///
/// 策略（设计文档 §7.3）：
/// - 默认只开「传输完成」音效，其余默认关闭，可在设置里逐项打开
/// - 同一事件 500ms 内去重，多文件连续完成不连响
/// - 音效走 `/System/Library/Sounds` 系统音，不打包音频资源
@MainActor
final class TransferNotification {

    // MARK: - 依赖

    /// 设置（提示音开关统一由 `TransferPreferences` 提供）
    private let preferences: TransferPreferences
    private let logger: LoggingService
    private let center = UNUserNotificationCenter.current()
    private var lastPlayed: [String: Date] = [:]
    /// 去重窗口（秒）
    private static let dedupeWindow: TimeInterval = 0.5

    init(preferences: TransferPreferences = TransferPreferences(),
         logger: LoggingService = AppContext.shared.logger) {
        self.preferences = preferences
        self.logger = logger
        requestAuthorization()
    }

    // MARK: - 文案

    /// 会话结束文案（面板提示与通知共用）
    static func message(for session: TransferSession) -> String {
        let direction = session.direction == .send ? "发送" : "接收"
        let count = session.files.count
        let names = session.files.prefix(2).map(\.name).joined(separator: "、")
        switch session.state {
        case .completed:
            return "\(direction)完成：\(names)\(count > 2 ? " 等 \(count) 个文件" : "")"
        case .failed:
            return "\(direction)失败：\(names)"
        case .cancelled:
            return "\(direction)已取消"
        default:
            return "\(direction)进行中"
        }
    }

    // MARK: - 事件

    /// 会话结束：发通知 + 播对应音效
    func sessionFinished(_ session: TransferSession) {
        let message = Self.message(for: session)
        switch session.state {
        case .completed:
            post(title: "传输完成", body: message)
            playIfEnabled(session.direction == .send ? .send : .receive,
                          soundName: session.direction == .send ? "Tink" : "Glass")
        case .failed:
            post(title: "传输失败", body: message)
            playIfEnabled(.failure, soundName: "Basso")
        case .cancelled:
            break
        default:
            break
        }
    }

    /// 新设备出现（默认关闭）
    func deviceAppeared(_ device: RemoteDevice) {
        playIfEnabled(.deviceAppeared, soundName: "Pop")
    }

    /// 配对码生成（默认关闭）
    func pairingCodeGenerated() {
        playIfEnabled(.pairingCode, soundName: "Morse")
    }

    // MARK: - 音效

    /// 按开关与去重窗口播放系统音
    private func playIfEnabled(_ event: TransferPreferences.SoundEvent, soundName: String) {
        guard preferences.soundEnabled(event) else { return }
        let now = Date()
        if let last = lastPlayed[event.rawValue], now.timeIntervalSince(last) < Self.dedupeWindow {
            return
        }
        lastPlayed[event.rawValue] = now
        guard let sound = NSSound(named: soundName) else {
            logger.debug("系统音效缺失：\(soundName)")
            return
        }
        sound.play()
    }

    // MARK: - 系统通知

    private func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { [logger] granted, error in
            if let error {
                logger.debug("通知授权失败（可能未签名）：\(error.localizedDescription)")
            } else if !granted {
                logger.debug("用户未授权传输完成通知")
            }
        }
    }

    private func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = nil
        let request = UNNotificationRequest(identifier: "transfer-\(UUID().uuidString)",
                                            content: content, trigger: nil)
        center.add(request) { [logger] error in
            if let error {
                logger.debug("通知投递失败：\(error.localizedDescription)")
            }
        }
    }
}
