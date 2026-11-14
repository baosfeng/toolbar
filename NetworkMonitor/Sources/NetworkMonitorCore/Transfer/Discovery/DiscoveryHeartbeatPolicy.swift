import Foundation

// MARK: - 发现层心跳退避策略

/// UDP 公告的心跳退避策略（纯值类型，不碰 socket，便于 TestRunner 断言）
///
/// 背景：本机没有可用组播出口时，5 秒一次的心跳会持续失败（实测 90 分钟 599 次
/// 「发送失败 errno=65」），既有 CPU 成本又刷日志。策略：
/// - 连续失败未达阈值：照常每拍发（偶发放包不该降频）；
/// - 达到阈值后按档位退避（30 秒 → 60 秒），期间心跳定时器照常推进设备存活判定；
/// - 任意一次发送成功立刻解除退避，回到 5 秒心跳。
///
/// 退避只作用于心跳公告：用户手动刷新（refreshDiscovery / announceNow）与
/// /24 扫描走各自的调用路径，不受本策略限制，因此发现灵敏度不会被拖慢。
public struct DiscoveryHeartbeatPolicy: Equatable, Sendable {

    /// 连续失败到这一档才开始退避
    public static let failureStreakBeforeBackoff = 3
    /// 退避档位（秒）：第 3 次失败 → 30 秒，第 4 次及以后 → 60 秒
    public static let backoffIntervals: [TimeInterval] = [30, 60]

    /// 当前连续失败次数
    public private(set) var failureStreak: Int
    /// 下一次允许发公告的最早时刻（nil = 立即可发）
    public private(set) var nextAnnounceAt: Date?

    public init(failureStreak: Int = 0, nextAnnounceAt: Date? = nil) {
        self.failureStreak = failureStreak
        self.nextAnnounceAt = nextAnnounceAt
    }

    /// 当前时刻是否该发公告
    public func shouldAnnounce(now: Date) -> Bool {
        guard let next = nextAnnounceAt else { return true }
        return now >= next
    }

    /// 记录一次公告结果
    /// - Parameters:
    ///   - success: 发送是否成功（sendto 返回值 >= 0）
    ///   - now: 本次发送时刻
    public mutating func noteAnnounce(success: Bool, now: Date) {
        guard !success else {
            failureStreak = 0
            nextAnnounceAt = nil
            return
        }
        failureStreak += 1
        guard failureStreak >= Self.failureStreakBeforeBackoff else { return }
        let index = min(failureStreak - Self.failureStreakBeforeBackoff,
                        Self.backoffIntervals.count - 1)
        nextAnnounceAt = now.addingTimeInterval(Self.backoffIntervals[index])
    }
}
