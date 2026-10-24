import Foundation

// MARK: - Token 用量计数

/// DSH token 用量计数（纯值类型，可跨线程传递）
///
/// 口径说明：
/// - uncachedInput 对应事件里的 inputTokens（未命中缓存的新增输入）
/// - cacheRead 对应 cacheReadTokens（命中缓存读取的输入）
/// - requestCount = 带 usage 的 assistant 消息条数，即发起的模型请求数
public struct HarnessTokenUsage: Sendable, Equatable {
    /// 未缓存输入 token
    public var uncachedInput: Int
    /// 输出 token
    public var output: Int
    /// 缓存读取 token
    public var cacheRead: Int
    /// 缓存写入 token
    public var cacheWrite: Int
    /// 请求数
    public var requestCount: Int

    /// 全零用量
    public static let zero = HarnessTokenUsage()

    public init(
        uncachedInput: Int = 0,
        output: Int = 0,
        cacheRead: Int = 0,
        cacheWrite: Int = 0,
        requestCount: Int = 0
    ) {
        self.uncachedInput = uncachedInput
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
        self.requestCount = requestCount
    }

    /// 总 token（未去重）：未缓存输入 + 输出 + 缓存读 + 缓存写
    public var totalTokens: Int { uncachedInput + output + cacheRead + cacheWrite }

    /// 是否完全没有数据
    public var isZero: Bool { totalTokens == 0 && requestCount == 0 }

    /// 累加（值语义，返回新值）
    public func adding(_ other: HarnessTokenUsage) -> HarnessTokenUsage {
        HarnessTokenUsage(
            uncachedInput: uncachedInput + other.uncachedInput,
            output: output + other.output,
            cacheRead: cacheRead + other.cacheRead,
            cacheWrite: cacheWrite + other.cacheWrite,
            requestCount: requestCount + other.requestCount
        )
    }
}

// MARK: - 缓存命中率

/// 缓存命中率口径（纯函数，便于测试）
public enum HarnessCacheHitRate {
    /// 缓存命中率 = cacheRead ÷ (cacheRead + uncachedInput)
    ///
    /// - Returns: 分母为 0 时返回 nil（表示「无数据」，不是 0%）
    public static func compute(cacheRead: Int, uncachedInput: Int) -> Double? {
        let denominator = cacheRead + uncachedInput
        guard denominator > 0 else { return nil }
        return Double(cacheRead) / Double(denominator)
    }
}

// MARK: - 按天 / 按项目 / 按模型

/// 单日用量（day 形如 "2026-10-24"，固定 Asia/Shanghai 时区）
public struct HarnessDailyUsage: Sendable, Equatable {
    public let day: String
    public let usage: HarnessTokenUsage

    public init(day: String, usage: HarnessTokenUsage) {
        self.day = day
        self.usage = usage
    }
}

/// 单小时用量（hour 0-23）
///
/// usage 为 nil 表示该小时「缺省」：无任何事件，或今日尚未到达该小时。
/// 缺省不补 0 —— 由 UI 决定画斜纹还是跳过。
public struct HarnessHourlyUsage: Sendable, Equatable {
    /// 上海时区自然小时（0-23）
    public let hour: Int
    /// 该小时用量；nil = 缺省（无数据 / 未来小时）
    public let usage: HarnessTokenUsage?

    public init(hour: Int, usage: HarnessTokenUsage?) {
        self.hour = hour
        self.usage = usage
    }

    /// 该小时是否有数据
    public var hasData: Bool { usage != nil }

    /// 00-23 共 24 槽、全部缺省的占位数组
    public static func emptyDay() -> [HarnessHourlyUsage] {
        (0..<24).map { HarnessHourlyUsage(hour: $0, usage: nil) }
    }
}

/// 单项目用量（path 保留完整路径，displayName 供 UI 展示）
public struct HarnessProjectUsage: Sendable, Equatable {
    public let path: String
    public let displayName: String
    public let sessionCount: Int
    public let usage: HarnessTokenUsage

    public init(path: String, displayName: String, sessionCount: Int, usage: HarnessTokenUsage) {
        self.path = path
        self.displayName = displayName
        self.sessionCount = sessionCount
        self.usage = usage
    }
}

/// 单模型用量
public struct HarnessModelUsage: Sendable, Equatable {
    public let provider: String
    public let model: String
    public let usage: HarnessTokenUsage

    public init(provider: String, model: String, usage: HarnessTokenUsage) {
        self.provider = provider
        self.model = model
        self.usage = usage
    }

    /// UI 展示名：provider 与 model 相同时只显示一项
    public var displayName: String {
        provider.isEmpty || provider == model ? model : provider + "/" + model
    }
}

// MARK: - 项目显示名

/// 项目显示名规则（纯函数）
public enum HarnessProjectNaming {
    /// 常见的中间聚合层目录：位于倒数第二级时省略，只显示项目目录名
    static let containerNames: Set<String> = [
        "IdeaProjects", "Documents", "Projects", "Desktop", "Downloads",
        "repos", "src", "work", "Code", "code", "workspace",
    ]

    /// 项目显示名：取最后一级；最后一级的父目录不是通用聚合层时保留两级以区分同名项目
    ///
    /// 例：/Users/me/IdeaProjects/my-dsh-plugins → my-dsh-plugins；
    /// /tmp/lab/exp-a → lab/exp-a
    public static func displayName(forPath path: String) -> String {
        var components = path.split(separator: "/").map(String.init)
        // 去掉根与 home 段（/Users/<name>/ 或 /home/<name>/）
        if components.count >= 3, components[0] == "Users" || components[0] == "home" {
            components.removeFirst(2)
        }
        guard let last = components.last else { return path }
        guard components.count >= 2 else { return last }
        let parent = components[components.count - 2]
        return containerNames.contains(parent) ? last : parent + "/" + last
    }
}

// MARK: - 汇总口径

/// 今日 / 本周 / 累计汇总
public struct HarnessUsageTotals: Sendable, Equatable {
    /// 今日（Asia/Shanghai 自然日）
    public let today: HarnessTokenUsage
    /// 本周（Asia/Shanghai，周一 00:00 起）
    public let thisWeek: HarnessTokenUsage
    /// 累计
    public let allTime: HarnessTokenUsage
    /// 累计缓存命中率；无输入数据时为 nil
    public let cacheHitRate: Double?

    public init(today: HarnessTokenUsage, thisWeek: HarnessTokenUsage, allTime: HarnessTokenUsage, cacheHitRate: Double?) {
        self.today = today
        self.thisWeek = thisWeek
        self.allTime = allTime
        self.cacheHitRate = cacheHitRate
    }
}

/// 索引聚合结果（索引库一次查询产出的原始数据，未做 TopN 与天数裁剪）
public struct HarnessAggregate: Sendable, Equatable {
    public let allTime: HarnessTokenUsage
    public let today: HarnessTokenUsage
    public let thisWeek: HarnessTokenUsage
    /// 按天升序，仅包含有数据的日期（无会话的日期不补 0）
    public let daily: [HarnessDailyUsage]
    /// 按总 token 降序
    public let projects: [HarnessProjectUsage]
    /// 按总 token 降序
    public let models: [HarnessModelUsage]
    /// 已建立扫描记录的会话数
    public let indexedSessions: Int
    /// 今日按小时（24 槽，nil = 缺省）
    public let todayHourly: [HarnessHourlyUsage]
    /// 昨日按小时（24 槽，nil = 缺省）
    public let yesterdayHourly: [HarnessHourlyUsage]

    public static let empty = HarnessAggregate(
        allTime: .zero, today: .zero, thisWeek: .zero,
        daily: [], projects: [], models: [], indexedSessions: 0,
        todayHourly: HarnessHourlyUsage.emptyDay(),
        yesterdayHourly: HarnessHourlyUsage.emptyDay()
    )

    public init(
        allTime: HarnessTokenUsage,
        today: HarnessTokenUsage,
        thisWeek: HarnessTokenUsage,
        daily: [HarnessDailyUsage],
        projects: [HarnessProjectUsage],
        models: [HarnessModelUsage],
        indexedSessions: Int,
        todayHourly: [HarnessHourlyUsage] = HarnessHourlyUsage.emptyDay(),
        yesterdayHourly: [HarnessHourlyUsage] = HarnessHourlyUsage.emptyDay()
    ) {
        self.allTime = allTime
        self.today = today
        self.thisWeek = thisWeek
        self.daily = daily
        self.projects = projects
        self.models = models
        self.indexedSessions = indexedSessions
        self.todayHourly = todayHourly
        self.yesterdayHourly = yesterdayHourly
    }
}

// MARK: - 对外快照

/// Token tab 对外快照（UI 只读此结构，不再直接碰数据库）
public struct HarnessUsageSnapshot: Sendable, Equatable {
    /// 今日 / 本周 / 累计
    public let totals: HarnessUsageTotals
    /// 趋势数据，最多 33 天，按天升序；无数据的日期保留为空缺（不插值、不补 0）
    public let daily: [HarnessDailyUsage]
    /// 今日 00-23 共 24 槽（Asia/Shanghai）；无数据 / 未到的小时为缺省
    public let todayHourly: [HarnessHourlyUsage]
    /// 昨日 00-23 共 24 槽，供「今日 vs 昨日同期」对比
    public let yesterdayHourly: [HarnessHourlyUsage]
    /// 项目 TopN
    public let projects: [HarnessProjectUsage]
    /// 模型 TopN
    public let models: [HarnessModelUsage]
    /// 已索引会话数
    public let indexedSessions: Int
    /// 发现到的会话文件总数
    public let totalSessions: Int
    /// 最近一次完成索引的时间
    public let lastScanAt: Date?
    /// 当前索引状态（供 UI 显示进度）
    public let indexingState: HarnessIndexingState
    /// 数据源可用性（zstd 或会话目录缺失时给出明确状态）
    public let sourceAvailability: HarnessSourceAvailability

    public init(
        totals: HarnessUsageTotals,
        daily: [HarnessDailyUsage],
        todayHourly: [HarnessHourlyUsage] = HarnessHourlyUsage.emptyDay(),
        yesterdayHourly: [HarnessHourlyUsage] = HarnessHourlyUsage.emptyDay(),
        projects: [HarnessProjectUsage],
        models: [HarnessModelUsage],
        indexedSessions: Int,
        totalSessions: Int,
        lastScanAt: Date?,
        indexingState: HarnessIndexingState,
        sourceAvailability: HarnessSourceAvailability
    ) {
        self.totals = totals
        self.daily = daily
        self.todayHourly = todayHourly
        self.yesterdayHourly = yesterdayHourly
        self.projects = projects
        self.models = models
        self.indexedSessions = indexedSessions
        self.totalSessions = totalSessions
        self.lastScanAt = lastScanAt
        self.indexingState = indexingState
        self.sourceAvailability = sourceAvailability
    }

    /// 空快照：索引尚未跑完时的占位值（UI 先拿到它渲染骨架，不等索引）
    public static func empty(
        availability: HarnessSourceAvailability,
        state: HarnessIndexingState
    ) -> HarnessUsageSnapshot {
        HarnessUsageSnapshot(
            totals: HarnessUsageTotals(today: .zero, thisWeek: .zero, allTime: .zero, cacheHitRate: nil),
            daily: [], projects: [], models: [],
            indexedSessions: 0, totalSessions: 0, lastScanAt: nil,
            indexingState: state, sourceAvailability: availability
        )
    }
}

// MARK: - 扫描产物

/// 单个会话文件的扫描产物（Scanner 交给 Service 的交接结构）
public struct HarnessSessionScanResult: Sendable, Equatable {
    public let sessionID: String
    /// 会话工作目录（来自 session 首行；项目归属只看这个，不从目录名反解）
    public let cwd: String
    /// 解析出的 usage 事件
    public let events: [HarnessTokenEvent]
    /// 总行数
    public let totalLines: Int
    /// 坏行 / 缺关键字段被跳过的行数
    public let malformedLines: Int
    /// 非目标事件（无 usage 的普通消息等）跳过行数
    public let ignoredLines: Int

    public init(sessionID: String, cwd: String, events: [HarnessTokenEvent], totalLines: Int, malformedLines: Int, ignoredLines: Int) {
        self.sessionID = sessionID
        self.cwd = cwd
        self.events = events
        self.totalLines = totalLines
        self.malformedLines = malformedLines
        self.ignoredLines = ignoredLines
    }
}
