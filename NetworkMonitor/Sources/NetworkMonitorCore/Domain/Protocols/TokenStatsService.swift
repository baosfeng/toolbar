import Foundation

// MARK: - 统计查询服务

/// Token 用量统计查询服务
public protocol TokenStatsService: AnyObject, Sendable {
    /// 查询今日汇总（按模型分组）
    func fetchTodaySummary() -> TodayTokenSummary
    /// 今日总计（快速）
    func fetchTodayTotal() -> (tokens: Int, cost: Double)
    /// 每小时明细
    func fetchHourlyBreakdown(dateString: String?) -> [HourlyTokenUsage]
    /// 每日历史
    func fetchDailyHistory(days: Int) -> [DailyTokenUsage]

    /// 工具调用排行
    func fetchToolCallRanking(limit: Int) -> [ToolCallStats]
    /// 最近工具调用
    func fetchRecentToolCalls(limit: Int) -> [RecentToolCall]
    /// 模型用量排行
    func fetchModelRanking(limit: Int) -> [ModelRanking]
    /// 项目用量排行
    func fetchProjectRanking(limit: Int) -> [ProjectRanking]
    /// 会话统计概览
    func fetchSessionOverviewStats() -> SessionOverviewStats
}
