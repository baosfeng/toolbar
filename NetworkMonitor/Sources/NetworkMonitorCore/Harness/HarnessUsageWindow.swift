import Foundation

// MARK: - 按范围聚合的窗口口径

/// Token 统计窗口 — 与 Token 页范围选择器一一对应
///
/// 与 `TokenRange`（展示层）刻意分开：数据层不该依赖展示层的枚举，
/// 映射关系写在 `TokenRange.window`（Token 目录），方向是「展示 → 数据」单向依赖。
public enum HarnessUsageWindow: Int, CaseIterable, Sendable, Equatable {
    /// 今日（上海自然日）
    case today
    /// 最近 7 天（含今日，共 7 个自然日）
    case last7Days
    /// 最近 30 天（含今日，共 30 个自然日）
    case last30Days

    /// 窗口天数（含今日）
    public var days: Int {
        switch self {
        case .today: return 1
        case .last7Days: return 7
        case .last30Days: return 30
        }
    }

    /// 卡头文案前缀（「今日 3 个 / 近 7 天 5 个」）
    public var title: String {
        switch self {
        case .today: return "今日"
        case .last7Days: return "近 7 天"
        case .last30Days: return "近 30 天"
        }
    }
}

// MARK: - 窗口边界

/// 窗口边界（毫秒；from 含、to 不含）
public struct HarnessMsWindow: Sendable, Equatable {
    public let fromMs: Int64
    public let toMs: Int64

    public init(fromMs: Int64, toMs: Int64) {
        self.fromMs = fromMs
        self.toMs = toMs
    }

    /// 是否包含该时间戳
    public func contains(tsMs: Int64) -> Bool {
        tsMs >= fromMs && tsMs < toMs
    }
}

/// 窗口边界的纯函数 —— 与 `TokenDerive.dailyBuckets(days:)` 的「含今日往前 N-1 天」一致
///
/// 之前「按项目 / 按模型」只算累计（无时间过滤），与 Hero / 四族卡的范围口径差 20~30 倍；
/// 这里把同一套边界交给 SQL 的 `WHERE ts_ms >= ? AND ts_ms < ?`，两处口径就不可能再分叉。
public enum HarnessRangeWindows {

    /// 指定窗口的毫秒边界
    public static func window(_ window: HarnessUsageWindow, now: Date) -> HarnessMsWindow {
        let todayStart = HarnessTokenTimeWindow.startOfDayMs(now: now)
        let dayMs = HarnessTokenTimeWindow.millisecondsPerDay
        let end = todayStart + dayMs
        let start = todayStart - Int64(window.days - 1) * dayMs
        return HarnessMsWindow(fromMs: start, toMs: end)
    }

    /// 一次给出三档边界（聚合时批量绑定参数用，顺序与 `allCases` 一致）
    public static func allWindows(now: Date) -> [(window: HarnessUsageWindow, range: HarnessMsWindow)] {
        HarnessUsageWindow.allCases.map { ($0, window($0, now: now)) }
    }
}

// MARK: - 按范围的项目 / 模型

/// 单个窗口内的项目与模型聚合
public struct HarnessWindowedUsage: Sendable, Equatable {
    /// 该窗口
    public let window: HarnessUsageWindow
    /// 按总 token 降序（未裁剪，裁剪在快照层按 TopN 做）
    public let projects: [HarnessProjectUsage]
    /// 按总 token 降序（未裁剪）
    public let models: [HarnessModelUsage]
    /// 该窗口内**全部**项目的 token 合计 —— 占比分母（用裁剪后的行求和会虚高占比）
    public let projectTotals: HarnessTokenUsage
    /// 该窗口内**全部**模型的 token 合计 —— 占比分母
    public let modelTotals: HarnessTokenUsage

    public init(window: HarnessUsageWindow,
                projects: [HarnessProjectUsage],
                models: [HarnessModelUsage],
                projectTotals: HarnessTokenUsage,
                modelTotals: HarnessTokenUsage) {
        self.window = window
        self.projects = projects
        self.models = models
        self.projectTotals = projectTotals
        self.modelTotals = modelTotals
    }

    /// 空窗口（无数据）
    public static func empty(_ window: HarnessUsageWindow) -> HarnessWindowedUsage {
        HarnessWindowedUsage(window: window, projects: [], models: [],
                             projectTotals: .zero, modelTotals: .zero)
    }
}
