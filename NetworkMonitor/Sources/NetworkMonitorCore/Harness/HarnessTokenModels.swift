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
    /// 累计口径的项目（按总 token 降序；保留给「累计」语义的旧调用方）
    public let projects: [HarnessProjectUsage]
    /// 累计口径的模型（按总 token 降序）
    public let models: [HarnessModelUsage]
    /// 按范围（今日 / 近 7 天 / 近 30 天）的项目与模型聚合（顺序同 `HarnessUsageWindow.allCases`）
    ///
    /// 存在理由：Hero / 四族卡 / 24 桶都跟随范围，而项目与模型原先只有累计口径，
    /// 同一屏两套口径导致「今日 340M」与「按项目 7.13B」差 20~30 倍。
    public let windowed: [HarnessWindowedUsage]
    /// 已建立扫描记录的会话数
    public let indexedSessions: Int
    /// 今日按小时（24 槽，nil = 缺省）
    public let todayHourly: [HarnessHourlyUsage]
    /// 昨日按小时（24 槽，nil = 缺省）
    public let yesterdayHourly: [HarnessHourlyUsage]

    public static let empty = HarnessAggregate(
        allTime: .zero, today: .zero, thisWeek: .zero,
        daily: [], projects: [], models: [], windowed: [], indexedSessions: 0,
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
        windowed: [HarnessWindowedUsage] = [],
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
        self.windowed = windowed
        self.indexedSessions = indexedSessions
        self.todayHourly = todayHourly
        self.yesterdayHourly = yesterdayHourly
    }
}
