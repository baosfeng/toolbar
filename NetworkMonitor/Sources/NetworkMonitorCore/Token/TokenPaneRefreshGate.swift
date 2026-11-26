import Foundation

// MARK: - Token 页切页时的刷新闸门（纯判据）

/// 切到 Token 页要不要真的发起一轮索引（TestRunner 直接断言）
///
/// 背景（用户原话「每次进入 Token 页都会快速地刷新一下」）：改前每次切页都无条件
/// `refreshIfNeeded()`，而首屏闭包里的 `refreshToken()` 内部又调一次 —— 一次切页排两次请求，
/// 且哪怕 3 秒前刚扫完也会重扫一遍。会话文件的更新粒度是秒级，60 秒内的重复扫描收益为零。
///
/// 判据沿用菜单栏 Token 指标的补拉间隔（`MenuBarTokenRefresh.interval`）：两条路径都在问
/// 「距离上次扫过够久了吗」，共用一个常量才不会出现「菜单栏 60s 就拉、面板 10s 就重扫」。
public enum TokenPaneRefreshGate {

    /// 两个时刻里更晚的那个（都缺 = nil）
    ///
    /// 索引完成时刻（`HarnessUsageSnapshot.lastScanAt`）与「上次真正排过请求的时刻」取晚者：
    /// 一轮索引跑到一半时 lastScanAt 还是上一轮的旧值，只用它会让用户连续切页排起一串请求。
    public static func lastActivity(indexedAt: Date?, requestedAt: Date?) -> Date? {
        switch (indexedAt, requestedAt) {
        case (nil, nil): return nil
        case (let a?, nil): return a
        case (nil, let b?): return b
        case (let a?, let b?): return max(a, b)
        }
    }

    /// 本次切页是否该发起索引
    ///
    /// - Parameters:
    ///   - indexedAt: 最近一次索引完成时刻（快照的 lastScanAt）
    ///   - requestedAt: 上次真正排过索引请求的时刻（调用方记，进程内状态）
    ///   - now: 本次时刻
    ///   - interval: 新鲜度窗口（<= 0 / 非有限时回落 `MenuBarTokenRefresh.interval`）
    public static func shouldRefresh(indexedAt: Date?,
                                     requestedAt: Date?,
                                     now: Date,
                                     interval customInterval: TimeInterval = MenuBarTokenRefresh.interval) -> Bool {
        guard let last = lastActivity(indexedAt: indexedAt, requestedAt: requestedAt) else { return true }
        let window = (customInterval.isFinite && customInterval > 0)
            ? customInterval
            : MenuBarTokenRefresh.interval
        let elapsed = now.timeIntervalSince(last)
        // 时钟回退（改系统时间）按「该刷新」处理：否则差值恒为负会永久不再刷新
        guard elapsed >= 0 else { return true }
        return elapsed >= window
    }
}
