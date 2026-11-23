import Foundation

// MARK: - 菜单栏 Token 指标的刷新口径

/// 菜单栏显示 Token 指标时的数据拉取判据
///
/// 为什么需要这一层：菜单栏的 Token 数字读的是 `HarnessUsageServicing.snapshot()`，而快照只在
/// 「一轮索引结束 / 有脏数据时按需重算」才变。索引原本只有三条触发路径 —— 后台自动监控定时器
/// （用户开关，缺键即关）、面板展开时的全量刷新、设置页手动重扫。于是默认配置下菜单栏的
/// `Token 713.9M` 会一直冻在某个值上，直到点开面板才跳一次，用户感知就是「菜单栏的 token 不实时」。
///
/// 因此补一条独立判据：**菜单栏只要显示着任一 Token 指标，就按固定间隔补拉一轮增量索引**。
/// 它不复用「后台自动监控」的间隔（那一项默认 300s、且是用户对 Token 页的显式设置），
/// 也不改那个开关的状态：这条路径只是为了让已上屏的数字不至于长期失真。
public enum MenuBarTokenRefresh {

    /// 菜单栏 Token 指标的补拉间隔（秒）
    ///
    /// 60s：一轮增量 = 一次目录枚举 + 一次扫描记录比对，无变更文件零解析；
    /// 比它更密没有收益（会话文件是秒级写入的，60s 粒度足够让数字「跟着走」）。
    public static let interval: TimeInterval = 60

    /// 会在菜单栏上显示 Token 数据的指标
    public static let tokenMetrics: Set<MenuBarMetric> = [.tokenToday, .tokenCacheHit, .tokenWeek]

    /// 给定启用集合里是否至少有一个 Token 指标（false = 菜单栏不展示 Token，不必补拉）
    public static func showsTokenMetric(_ enabled: Set<MenuBarMetric>) -> Bool {
        !enabled.isDisjoint(with: tokenMetrics)
    }

    /// 本轮是否该补拉一次增量索引
    ///
    /// - Parameters:
    ///   - enabled: 菜单栏已启用的指标集合
    ///   - lastPullAt: 上次补拉时刻（nil = 还没拉过）
    ///   - now: 本轮时刻
    ///   - interval: 自定义间隔（<= 0 / 非有限时回落 `interval`）
    public static func needsPull(enabled: Set<MenuBarMetric>,
                                 lastPullAt: Date?,
                                 now: Date,
                                 interval customInterval: TimeInterval = interval) -> Bool {
        guard showsTokenMetric(enabled) else { return false }
        guard let lastPullAt else { return true }
        let seconds = (customInterval.isFinite && customInterval > 0) ? customInterval : interval
        let elapsed = now.timeIntervalSince(lastPullAt)
        // 时钟回退（改了系统时间）按「该拉」处理：否则差值恒为负会永久卡死
        guard elapsed >= 0 else { return true }
        return elapsed >= seconds
    }
}
