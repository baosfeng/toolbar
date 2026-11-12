import Foundation

// MARK: - 剪贴板轮询调度（纯函数）

/// 剪贴板采集的轮询间隔决策（对标 OneClip 的按活跃度动态轮询，增量规格 2.2 增量 B）
///
/// 纯函数：不依赖 AppKit / 计时器 / 全局状态，相同入参必定相同出参，可直接被 TestRunner 断言。
/// 调用方（PasteboardWatcher）每次 tick 前重算一次间隔，用一次性 Timer 链式重排，
/// 不做「每秒重建 Timer」这类抖动写法。
public enum ClipboardPollSchedule {

    /// 最快档：用户刚有输入事件且本 App 在前台（与原有固定 500ms 轮询同档）
    public static let activeInterval: TimeInterval = 0.5
    /// 次快档：用户仍在用电脑但本 App 不在前台，或活跃时间已过 30s
    public static let warmInterval: TimeInterval = 2.0
    /// 最慢档：用户长时间无输入（≥ 5 分钟）
    public static let idleInterval: TimeInterval = 5.0

    /// 活跃阈值（秒）：空闲低于此值且本 App 前台才走最快档
    public static let activeIdleThreshold: TimeInterval = 30
    /// 空闲阈值（秒）：空闲达到此值后只保留最慢档
    public static let idleThreshold: TimeInterval = 300

    /// 归一化空闲秒数：负数 / NaN / 正负无穷一律按 0 处理（走最快档，宁可多轮询也不漏采）
    public static func normalizedIdleSeconds(_ idleSeconds: TimeInterval) -> TimeInterval {
        guard idleSeconds.isFinite, idleSeconds > 0 else { return 0 }
        return idleSeconds
    }

    /// 下一次轮询间隔
    ///
    /// 档位（设计规格 2.2 第 1 条）：
    /// - `idleSeconds < 30 && isAppActive` → 0.5s
    /// - `idleSeconds < 300` → 2.0s（本 App 非前台但用户仍在用电脑时落此档，不再走最快档）
    /// - 其余 → 5.0s
    public static func interval(idleSeconds: TimeInterval, isAppActive: Bool) -> TimeInterval {
        let idle = normalizedIdleSeconds(idleSeconds)
        if idle >= idleThreshold { return idleInterval }
        if idle < activeIdleThreshold && isAppActive { return activeInterval }
        return warmInterval
    }

    /// 链式 Timer 下一次重排的间隔；`nil` = 不再排下一次（已停止）
    ///
    /// 采集器每次 tick 只调用这一个函数：停止后无论入参多活跃都不会再排 tick，
    /// 「停不下来」与「停止后仍 tick」两类问题因此在纯函数层即可断言。
    public static func nextInterval(isRunning: Bool,
                                    idleSeconds: TimeInterval,
                                    isAppActive: Bool) -> TimeInterval? {
        guard isRunning else { return nil }
        return interval(idleSeconds: idleSeconds, isAppActive: isAppActive)
    }
}
