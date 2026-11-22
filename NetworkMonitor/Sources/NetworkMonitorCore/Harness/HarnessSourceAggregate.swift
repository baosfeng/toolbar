import Foundation

// MARK: - 单来源聚合

/// 单个来源的用量（冻结契约：Token 页用它的 sessionCount 与「有数据的来源清单」）
///
/// usage 是**累计**口径（与 snapshot.totals.allTime 同源）：只给一个总数时不至于让调用方
/// 误以为它是当前范围。要按范围取数走 `HarnessUsageSnapshot.scoped(to:)`（与全量同形）。
public struct HarnessSourceUsage: Sendable, Equatable {
    /// 该来源的累计用量
    public let usage: HarnessTokenUsage
    /// 该来源已建立扫描记录的会话数
    public let sessionCount: Int

    public init(usage: HarnessTokenUsage, sessionCount: Int) {
        self.usage = usage
        self.sessionCount = sessionCount
    }
}

// MARK: - 单来源聚合明细

/// 单个来源的完整聚合（字段与 `HarnessAggregate` 同形，去掉再嵌套的 bySource）
///
/// 为什么要整份留着而不是只留一个总数：Token 页切到单一来源时，Hero / 四族卡 /
/// 趋势 / 缓存 / 排行都要等于「该源自己的聚合」。若快照只带一个计数器，界面要么只能
/// 显示累计总量，要么得为单源再跑一遍全表聚合（每切一次来源 0.2~1 s）。
/// 因此聚合阶段按来源各算一份、随快照缓存，切来源是零查询。
public struct HarnessSourceAggregate: Sendable, Equatable {
    public let allTime: HarnessTokenUsage
    public let today: HarnessTokenUsage
    public let thisWeek: HarnessTokenUsage
    /// 按天升序，仅含有数据的日期（口径与全量一致）
    public let daily: [HarnessDailyUsage]
    /// 累计口径的项目（按总 token 降序，未裁剪）
    public let projects: [HarnessProjectUsage]
    /// 累计口径的模型（按总 token 降序，未裁剪）
    public let models: [HarnessModelUsage]
    /// 三档窗口的项目 / 模型（顺序同 HarnessUsageWindow.allCases）
    public let windowed: [HarnessWindowedUsage]
    /// 今日按小时（24 槽，nil = 缺省）
    public let todayHourly: [HarnessHourlyUsage]
    /// 昨日按小时（24 槽，nil = 缺省）
    public let yesterdayHourly: [HarnessHourlyUsage]
    /// 该来源已建立扫描记录的会话数
    public let indexedSessions: Int

    public static let empty = HarnessSourceAggregate(
        allTime: .zero, today: .zero, thisWeek: .zero,
        daily: [], projects: [], models: [], windowed: [],
        todayHourly: HarnessHourlyUsage.emptyDay(),
        yesterdayHourly: HarnessHourlyUsage.emptyDay(),
        indexedSessions: 0
    )

    public init(
        allTime: HarnessTokenUsage,
        today: HarnessTokenUsage,
        thisWeek: HarnessTokenUsage,
        daily: [HarnessDailyUsage],
        projects: [HarnessProjectUsage],
        models: [HarnessModelUsage],
        windowed: [HarnessWindowedUsage] = [],
        todayHourly: [HarnessHourlyUsage] = HarnessHourlyUsage.emptyDay(),
        yesterdayHourly: [HarnessHourlyUsage] = HarnessHourlyUsage.emptyDay(),
        indexedSessions: Int
    ) {
        self.allTime = allTime
        self.today = today
        self.thisWeek = thisWeek
        self.daily = daily
        self.projects = projects
        self.models = models
        self.windowed = windowed
        self.todayHourly = todayHourly
        self.yesterdayHourly = yesterdayHourly
        self.indexedSessions = indexedSessions
    }

    /// 该来源是否有任何数据（决定 UI 要不要把它列进来源清单）
    public var hasData: Bool {
        !allTime.isZero || indexedSessions > 0
    }
}
