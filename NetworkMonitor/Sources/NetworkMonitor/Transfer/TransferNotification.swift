import AppKit
import NetworkMonitorCore

// MARK: - 传输通知与音效

/// 传输通知 — 完成 / 失败的系统通知与提示音
///
/// 策略（统一到「通知与音效」设置页的传输完成一行）：
/// - 通知走 NotificationCenterService，声音与提醒方式由设置页决定；
/// - 系统通知未授权时退化为应用内提示音（否则用户什么都收不到）；
/// - 同一事件 500ms 内去重，多文件连续完成不连响；
/// - 「新设备出现」「配对码生成」两个旧开关并入传输完成一行：
///   它们默认关闭、且与传输完成同一时机，独立成行只会让设置页多两行没人调的开关。
@MainActor
final class TransferNotification {

    // MARK: - 依赖

    private let notifications: any NotificationServicing
    private let soundPlayer: NotificationSoundPlayer
    private let logger: LoggingService
    private var lastPlayed: [String: Date] = [:]
    /// 去重窗口（秒）
    private static let dedupeWindow: TimeInterval = 0.5

    init(notifications: any NotificationServicing,
         soundPlayer: NotificationSoundPlayer,
         logger: LoggingService = AppContext.shared.logger) {
        self.notifications = notifications
        self.soundPlayer = soundPlayer
        self.logger = logger
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

    /// 会话结束：发通知（系统通知可用）或播应用内提示音（不可用）
    func sessionFinished(_ session: TransferSession) {
        let message = Self.message(for: session)
        switch session.state {
        case .completed:
            deliver(title: "传输完成", body: message)
        case .failed:
            deliver(title: "传输失败", body: message)
        case .cancelled, .pending, .offering, .awaitingConfirm, .transferring, .verifying:
            break
        }
    }

    // MARK: - 内部

    /// 发通知；未授权时退化为应用内提示音（同一事件 500ms 内只响一次）
    private func deliver(title: String, body: String) {
        if notifications.authorizationState == .authorized {
            notifications.post(NotificationMessage(event: .transferFinished,
                                                   title: title, body: body))
            return
        }
        guard passesDedupe() else { return }
        soundPlayer.play(event: .transferFinished, cue: .transferFinished)
        logger.debug("系统通知未授权，改为应用内提示音：\(title)")
    }

    /// 去重：多文件连续完成时只响一次
    private func passesDedupe() -> Bool {
        let now = Date()
        if let last = lastPlayed["transferFinished"], now.timeIntervalSince(last) < Self.dedupeWindow {
            return false
        }
        lastPlayed["transferFinished"] = now
        return true
    }
}
