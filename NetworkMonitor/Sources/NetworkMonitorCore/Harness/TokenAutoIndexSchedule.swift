import Foundation

// MARK: - 自动监控时间口径（纯函数）

/// Token 后台自动监控的时间口径
///
/// 放在 Core 而不是 App：这是「什么时候该扫」的纯口径，测试要能直接断言
/// （TestRunner 依赖不含 App 可执行 target）。App 侧的 `TokenAutoIndexScheduler`
/// 只负责定时器、订阅与探针，不再自带一套计算。
///
/// 行为契约（改这里等于改产品行为）：
/// - 间隔缺键 300s、写入值 ≤0 或非有限按 300s；下限 60s；
/// - 下一次触发 = **本轮结束时间** + 归一后的间隔（一轮结束才重排，不追帧）。
public enum TokenAutoIndexSchedule {

    /// 启动 / 唤醒后的首次触发延迟（秒）
    ///
    /// 不设 0：启动期同时在装配、建菜单栏、读数据库，立刻扫一遍会和它们抢 IO；
    /// 1 秒足够让启动期的一次性工作先落地，也不至于让用户觉得「开了却不动」。
    public static let firstFireDelay: TimeInterval = 1

    /// 间隔归一（唯一口径在 TokenSourcePreferences，这里只是转调，避免两处各写一份）
    public static func normalizedInterval(_ raw: TimeInterval) -> TimeInterval {
        TokenSourcePreferences.normalizedInterval(raw)
    }

    /// 下一次触发时间 = 本轮结束时间 + 间隔（不追帧）
    ///
    /// 为什么基准是「结束」而不是「开始」：一轮耗时超过间隔时（大目录首轮全量），
    /// 按开始时间排会让下一轮立刻开始，形成背靠背连续扫描；按结束时间排则永远留出
    /// 一个完整间隔的喘息，代价是实测周期略大于配置值（可接受）。
    public static func nextFireDate(after roundEndedAt: Date, interval: TimeInterval) -> Date {
        roundEndedAt.addingTimeInterval(normalizedInterval(interval))
    }
}
