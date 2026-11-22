import Foundation

// MARK: - 对外快照与扫描产物

/// 从 HarnessTokenModels.swift 拆出（主文件贴单单文件 15 KiB 上限）
///
/// 这两块是「服务 ↔ UI」「扫描器 ↔ 服务」的交接结构，与计数 / 聚合模型职责不同：
/// 前者是内存中的值类型定义，后者是跨模块的边界契约。

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
    /// 项目 TopN（累计口径；`windowedProjects` 才是页面实际使用的那份）
    public let projects: [HarnessProjectUsage]
    /// 模型 TopN（累计口径）
    public let models: [HarnessModelUsage]
    /// 按范围的项目 TopN（键为窗口；页面按当前范围取用）
    public let windowedProjects: [HarnessUsageWindow: [HarnessProjectUsage]]
    /// 按范围的模型 TopN
    public let windowedModels: [HarnessUsageWindow: [HarnessModelUsage]]
    /// 按范围的占比分母（该窗口内全部项目 / 模型的 token 合计）
    public let windowProjectTotals: [HarnessUsageWindow: HarnessTokenUsage]
    /// 同上（模型）
    public let windowModelTotals: [HarnessUsageWindow: HarnessTokenUsage]
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
    /// 数据源诊断（会话目录路径 + 来源 + zstd 实际路径 / 缺失原因）
    ///
    /// 带默认值：既有构造点（测试与快照冻结）不改也能编译，
    /// 诊断缺省时按可用性兜底推一份，UI 不会读到空。
    public let sourceDiagnostics: HarnessSourceDiagnostics
    /// 按来源的完整聚合（键缺失 = 该来源未索引到）
    ///
    /// 存明细而不是「已裁好的单源快照」：同一份数据既能出 bySource 的计数，
    /// 也能出 scoped(to:) 的同形快照，还不必为每个来源各存一份 33 天趋势。
    public let perSourceAggregates: [TokenSourceID: HarnessSourceAggregate]
    /// 按来源的可用性（scoped(to:) 用它给单源口径；缺省回落全量口径）
    public let sourceAvailabilityBySource: [TokenSourceID: HarnessSourceAvailability]
    /// 按来源的诊断（同上）
    public let sourceDiagnosticsBySource: [TokenSourceID: HarnessSourceDiagnostics]

    public init(
        totals: HarnessUsageTotals,
        daily: [HarnessDailyUsage],
        todayHourly: [HarnessHourlyUsage] = HarnessHourlyUsage.emptyDay(),
        yesterdayHourly: [HarnessHourlyUsage] = HarnessHourlyUsage.emptyDay(),
        projects: [HarnessProjectUsage],
        models: [HarnessModelUsage],
        windowedProjects: [HarnessUsageWindow: [HarnessProjectUsage]] = [:],
        windowedModels: [HarnessUsageWindow: [HarnessModelUsage]] = [:],
        windowProjectTotals: [HarnessUsageWindow: HarnessTokenUsage] = [:],
        windowModelTotals: [HarnessUsageWindow: HarnessTokenUsage] = [:],
        indexedSessions: Int,
        totalSessions: Int,
        lastScanAt: Date?,
        indexingState: HarnessIndexingState,
        sourceAvailability: HarnessSourceAvailability,
        sourceDiagnostics: HarnessSourceDiagnostics? = nil,
        perSourceAggregates: [TokenSourceID: HarnessSourceAggregate] = [:],
        sourceAvailabilityBySource: [TokenSourceID: HarnessSourceAvailability] = [:],
        sourceDiagnosticsBySource: [TokenSourceID: HarnessSourceDiagnostics] = [:]
    ) {
        self.totals = totals
        self.daily = daily
        self.todayHourly = todayHourly
        self.yesterdayHourly = yesterdayHourly
        self.projects = projects
        self.models = models
        self.windowedProjects = windowedProjects
        self.windowedModels = windowedModels
        self.windowProjectTotals = windowProjectTotals
        self.windowModelTotals = windowModelTotals
        self.indexedSessions = indexedSessions
        self.totalSessions = totalSessions
        self.lastScanAt = lastScanAt
        self.indexingState = indexingState
        self.sourceAvailability = sourceAvailability
        // 调用方没给诊断时按可用性推一份：UI 永远读得到「哪个目录 / 缺什么」，不会读到空
        self.sourceDiagnostics = sourceDiagnostics
            ?? HarnessSourceDiagnostics.make(availability: sourceAvailability)
        self.perSourceAggregates = perSourceAggregates
        self.sourceAvailabilityBySource = sourceAvailabilityBySource
        self.sourceDiagnosticsBySource = sourceDiagnosticsBySource
    }

    /// 空快照：索引尚未跑完时的占位值（UI 先拿到它渲染骨架，不等索引）
    public static func empty(
        availability: HarnessSourceAvailability,
        state: HarnessIndexingState,
        diagnostics: HarnessSourceDiagnostics? = nil
    ) -> HarnessUsageSnapshot {
        HarnessUsageSnapshot(
            totals: HarnessUsageTotals(today: .zero, thisWeek: .zero, allTime: .zero, cacheHitRate: nil),
            daily: [], projects: [], models: [],
            indexedSessions: 0, totalSessions: 0, lastScanAt: nil,
            indexingState: state, sourceAvailability: availability,
            sourceDiagnostics: diagnostics
        )
    }

    /// 只换索引状态（其余字段原样保留）—— 状态机推进时避免把十几个字段抄一遍
    public func with(indexingState: HarnessIndexingState) -> HarnessUsageSnapshot {
        HarnessUsageSnapshot(
            totals: totals,
            daily: daily,
            todayHourly: todayHourly,
            yesterdayHourly: yesterdayHourly,
            projects: projects,
            models: models,
            windowedProjects: windowedProjects,
            windowedModels: windowedModels,
            windowProjectTotals: windowProjectTotals,
            windowModelTotals: windowModelTotals,
            indexedSessions: indexedSessions,
            totalSessions: totalSessions,
            lastScanAt: lastScanAt,
            indexingState: indexingState,
            sourceAvailability: sourceAvailability,
            sourceDiagnostics: sourceDiagnostics,
            perSourceAggregates: perSourceAggregates,
            sourceAvailabilityBySource: sourceAvailabilityBySource,
            sourceDiagnosticsBySource: sourceDiagnosticsBySource
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