import Foundation

// MARK: - 最小间隔节流原语

/// 最小间隔节流闸门 —— 距上次放行不足 `interval` 时拒绝（纯值类型，可跨隔离域复制）
///
/// 判断与理由：
/// - 首次恒放行：还没有上次放行时刻，说明这是第一拍，节流没有参照物；
/// - 拒绝时**不**推进 `lastRunAt`：否则高频调用会不断顺延窗口，节流窗口被无限拉长；
/// - 时钟回退（本次时刻早于上次放行）按放行处理并重置：系统时间被改回后
///   差值恒为负，若照常拒绝会永久卡死，宁可多放一次；
/// - `interval <= 0` 视为不节流：调用方传 0 的意图就是每次都跑。
public struct MinimumIntervalGate: Sendable {

    /// 最小间隔（秒）
    public let interval: TimeInterval

    /// 上次放行的时刻（nil = 还没有放行过）
    public private(set) var lastRunAt: Date?

    /// - Parameter lastRunAt: 既有的上次放行时刻（nil = 还没有放行过）
    ///
    /// 允许显式承接：调用方的间隔随可见性 / 档位变化时，换了间隔仍要沿用同一个窗口，
    /// 否则每次换间隔都会多放行一次；从「自己记一个 Date」迁移过来的调用方也靠它保持等价。
    public init(interval: TimeInterval, lastRunAt: Date? = nil) {
        self.interval = interval
        self.lastRunAt = lastRunAt
    }

    /// 本次是否放行；放行时把 `now` 记为新的 `lastRunAt`
    public mutating func shouldRun(now: Date = Date()) -> Bool {
        guard let last = lastRunAt else {
            lastRunAt = now
            return true
        }

        let elapsed = now.timeIntervalSince(last)
        guard elapsed >= 0 else {
            lastRunAt = now
            return true
        }
        guard elapsed >= interval else { return false }
        lastRunAt = now
        return true
    }
}
