import Foundation

// MARK: - 采集暂停（纯口径）

/// 剪贴板采集暂停的纯口径 —— 默认值、可见文案与菜单标题
///
/// 与 `ClipboardCaptureMode`（怎么采）是两个维度：这里决定「采不采」。
/// 全部为纯函数，不依赖 AppKit / 偏好存储，供面板、菜单栏、设置页与 TestRunner 共用一份口径。
public enum ClipboardPauseLogic {

    /// 切换暂停的组合键（面板键位帮助浮层与提示行共用同一份文字）
    public static let toggleKeyHint = "⌘P"

    /// 暂停开关的默认值：未写入过即未暂停（老用户升级后行为不变）
    public static func isPaused(storedValue: Bool?) -> Bool {
        storedValue ?? false
    }

    /// 是否需要真的执行一次暂停 / 恢复（幂等判据）
    ///
    /// 暂停与恢复共用这一条：目标态与当前态相同即无事可做，调用方不得重复停轮询、
    /// 重复注册观察者或重复打日志。实现与测试共用同一份口径，避免两处各写一遍。
    public static func shouldTransition(currentlyPaused: Bool, target: Bool) -> Bool {
        currentlyPaused != target
    }

    /// 提示行空闲文案：暂停时常驻「已暂停」（定时暂停带出截止时刻），否则回到键位帮助
    ///
    /// - Parameters:
    ///   - isPaused: 当前是否暂停
    ///   - pausedUntil: 定时暂停的截止时刻（哨兵值 = 无定时）
    ///   - now: 判定「有无定时」的当前时刻（默认系统时钟，测试注入）
    ///   - idleHint: 未暂停时的键位帮助文案
    public static func footerHint(isPaused: Bool,
                                  pausedUntil: Date = .distantPast,
                                  now: Date = Date(),
                                  idleHint: String) -> String {
        guard isPaused else { return idleHint }
        guard hasTimedEnd(pausedUntil: pausedUntil, now: now) else {
            return "采集已暂停（点此或 \(toggleKeyHint) 恢复）"
        }
        return "采集暂停至 \(clockText(pausedUntil))（点此或 \(toggleKeyHint) 恢复）"
    }

    // MARK: - 定时暂停

    /// 定时暂停的时长档位（设置页下拉的三个预设 + 到手动恢复）
    public enum PauseDuration: Int, CaseIterable, Sendable {
        /// 手动恢复：不写截止时刻，暂停到用户自己点恢复
        case manual = 0
        case fifteenMinutes = 15
        case oneHour = 60
        case fourHours = 240

        /// 设置页下拉标题
        public var label: String {
            switch self {
            case .manual: return "到手动恢复"
            case .fifteenMinutes: return "15 分钟"
            case .oneHour: return "1 小时"
            case .fourHours: return "4 小时"
            }
        }

        /// 选中该档位后的截止时刻；手动恢复返回哨兵值（不写定时）
        public func endDate(now: Date) -> Date {
            guard rawValue > 0 else { return .distantPast }
            return now.addingTimeInterval(Double(rawValue) * 60)
        }
    }

    /// 定时截止时刻是否仍然有效（缺失 / 手动暂停一律视为无定时）
    ///
    /// 判据用「时间戳 > 0」而不是与 .distantPast 相等：偏好缺失读出来是 1970 纪元时间戳 0，
    /// 与 .distantPast（公元 1 年）都表示「没有定时」，只认一种会把另一种误判成已过期。
    public static func hasTimedEnd(pausedUntil: Date, now: Date) -> Bool {
        pausedUntil.timeIntervalSince1970 > 0 && now < pausedUntil
    }

    /// 当前是否处于暂停态 —— 定时暂停到点自动失效，手动暂停不过期
    ///
    /// - Parameters:
    ///   - paused: 偏好里记录的暂停开关
    ///   - pausedUntil: 定时暂停的截止时刻（哨兵值 = 无定时）
    ///   - now: 当前时刻
    public static func isPausedNow(paused: Bool, pausedUntil: Date, now: Date) -> Bool {
        guard paused else { return false }
        guard pausedUntil.timeIntervalSince1970 > 0 else { return true }
        return now < pausedUntil
    }

    /// 定时暂停的剩余整分钟（向上取整：还剩 30 秒也说 1 分钟，
    /// 不出现「还剩 0 分钟却仍在暂停」）
    ///
    /// 无定时（含偏好缺失）与已到点都返回 0，调用方据此决定是否展示剩余时长。
    public static func remainingMinutes(pausedUntil: Date, now: Date) -> Int {
        let seconds = pausedUntil.timeIntervalSince(now)
        guard pausedUntil.timeIntervalSince1970 > 0, seconds > 0 else { return 0 }
        return Int((seconds / 60).rounded(.up))
    }

    /// 截止时刻的时钟文本（HH:mm），面板与设置页共用同一口径
    public static func clockText(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        guard let hour = parts.hour, let minute = parts.minute else { return "--:--" }
        return String(format: "%02d:%02d", hour, minute)
    }

    /// 右键菜单项标题：按当前状态给出「接下来能做的事」
    public static func menuTitle(isPaused: Bool) -> String {
        isPaused ? "恢复采集" : "暂停采集"
    }

    /// 状态栏标题前缀：暂停时给一个可辨识的标记，正常时为空串
    public static func statusPrefix(isPaused: Bool) -> String {
        isPaused ? "⏸ " : ""
    }

    /// 暂停态点「采集当前剪贴板」被拒的提示（不得静默）
    public static var captureBlockedHint: String {
        "采集已暂停（\(toggleKeyHint) 或菜单「恢复采集」可恢复）"
    }
}
