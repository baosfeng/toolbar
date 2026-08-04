import Foundation
import SQLite3

// MARK: - 数据模型

/// 按模型的 token 用量
public struct TokenUsageByModel: Sendable, Equatable {
    public let model: String
    public let promptTokens: Int
    public let completionTokens: Int
    public let totalTokens: Int
    public let cost: Double
}

/// 每小时的 token 用量
public struct HourlyTokenUsage: Sendable, Equatable {
    public let hour: Int  // 0–23
    public let promptTokens: Int
    public let completionTokens: Int
    public let totalTokens: Int
    public let cost: Double
}

/// 每日 token 用量汇总
public struct DailyTokenUsage: Sendable, Equatable {
    public let date: String  // "2026-07-25"
    public let totalTokens: Int
    public let promptTokens: Int
    public let completionTokens: Int
    public let cost: Double
}

/// 今日汇总（总计 + 按模型）
public struct TodayTokenSummary: Sendable, Equatable {
    public let totalTokens: Int
    public let totalCost: Double
    public let byModel: [TokenUsageByModel]
}

// MARK: - AI 分析数据模型

/// 工具调用统计
public struct ToolCallStats: Sendable, Equatable {
    public let toolName: String
    public let callCount: Int
    public let successCount: Int
    public let failCount: Int
    public let successRate: Double
    public let avgDurationMs: Int
}

/// 最近工具调用
public struct RecentToolCall: Sendable, Equatable {
    public let toolName: String
    public let status: String
    public let durationMs: Int
    public let secondsAgo: Int
    public let sessionId: String
}

/// 模型用量排行
public struct ModelRanking: Sendable, Equatable {
    public let model: String
    public let totalTokens: Int
    public let totalCost: Double
    public let sessionCount: Int
}

/// 项目用量排行
public struct ProjectRanking: Sendable, Equatable {
    public let project: String
    public let totalTokens: Int
    public let sessionCount: Int
    public let totalCost: Double
}

/// 会话统计概览
public struct SessionOverviewStats: Sendable, Equatable {
    public let activeSessions: Int
    public let todayTotal: Int
    public let todayFailed: Int
    public let failRate: Double
    public let reasoningTokenRatio: Double
}

// MARK: - Token 用量查询器

/// Token 用量统计查询器。
///
/// 统计口径与 reasonix 官方一致：读取 `<state root>/stats/YYYY-MM-DD.jsonl`，
/// 每条记录是一次模型调用的**增量**（`total` 为单次调用 token 数），
/// 文件按本地日期命名、`ts` 自带时区，因此按天求和即当天真实用量，
/// 无需任何时区偏移转换。历史 hook 事件中的 token 快照不再作为统计来源。
public final class TokenUsageProvider: TokenStatsService {

    private let database: DatabaseManager
    private let statsDir: String

    public init(database: DatabaseManager, statsDir: String? = nil) {
        self.database = database
        self.statsDir = statsDir ?? ReasonixStatsLoader.defaultStatsDir()
    }

    // MARK: - 今日汇总

    /// 查询今日 token 用量汇总（按模型分组）
    /// 数据源：今日 stats 文件（增量记录求和）
    public func fetchTodaySummary() -> TodayTokenSummary {
        let today = todayDateString()
        let records = ReasonixStatsLoader.loadDay(statsDir: statsDir, date: today)
        let byModel = ReasonixStatsLoader.totalsByModel(records)

        var grandTotalTokens = 0
        var grandTotalCost = 0.0
        var models: [TokenUsageByModel] = []
        for m in byModel {
            grandTotalTokens += m.total
            models.append(TokenUsageByModel(
                model: m.model,
                promptTokens: m.prompt,
                completionTokens: m.completion,
                totalTokens: m.total,
                cost: 0
            ))
        }
        // 花费仍来自 hook 会话汇总（per-session 累计 cost，历史数据已清理后重新积累）
        grandTotalCost = todaySessionCost(today: today)

        return TodayTokenSummary(
            totalTokens: grandTotalTokens,
            totalCost: grandTotalCost,
            byModel: models
        )
    }

    /// 今日总计（快速查询，无需分组）
    /// token 来自今日 stats 文件；花费来自今日结束的 hook 会话累计 cost
    public func fetchTodayTotal() -> (tokens: Int, cost: Double) {
        let today = todayDateString()
        let tokens = ReasonixStatsLoader.totalTokens(statsDir: statsDir, date: today)
        let cost = todaySessionCost(today: today)
        return (tokens, cost)
    }

    /// 今日 hook 会话累计花费（CNY，per-session 累计 cost 之和）
    private func todaySessionCost(today: String) -> Double {
        let sql = """
            SELECT COALESCE(SUM(total_cost), 0.0)
            FROM hook_sessions
            WHERE date(started_at, 'localtime') = '\(today)'
            """
        var cost = 0.0
        database.query(sql: sql) { stmt in
            cost = sqlite3_column_double(stmt, 0)
        }
        return cost
    }

    // MARK: - 每小时明细

    /// 查询指定日期的每小时 token 用量明细
    /// 数据源：stats 文件中 ts 字段解析为本地时间后按小时分组（ts 自带时区，无需偏移）
    /// - Parameter dateString: "2026-07-25" 格式，传 nil 则查今天
    public func fetchHourlyBreakdown(dateString: String? = nil) -> [HourlyTokenUsage] {
        let day = dateString ?? todayDateString()
        let records = ReasonixStatsLoader.loadDay(statsDir: statsDir, date: day)

        var byHour: [Int: (prompt: Int, completion: Int, total: Int)] = [:]
        for r in records where !r.isTurn {
            guard let ts = ReasonixStatsLoader.parseTimestamp(r.ts),
                  ts.ymdString() == day else { continue }
            let hour = Calendar.current.component(.hour, from: ts)
            var acc = byHour[hour] ?? (0, 0, 0)
            acc.prompt += r.promptTokens
            acc.completion += r.completionTokens
            acc.total += r.totalTokens
            byHour[hour] = acc
        }

        var filled: [HourlyTokenUsage] = []
        for hour in 0..<24 {
            if let acc = byHour[hour] {
                filled.append(HourlyTokenUsage(hour: hour, promptTokens: acc.prompt,
                                               completionTokens: acc.completion,
                                               totalTokens: acc.total, cost: 0))
            } else {
                filled.append(HourlyTokenUsage(hour: hour, promptTokens: 0, completionTokens: 0, totalTokens: 0, cost: 0))
            }
        }
        return filled
    }

    // MARK: - 每日历史

    /// 查询最近 N 天的每日汇总
    /// 数据源：stats 目录中按日期命名的文件（本地日期）
    public func fetchDailyHistory(days: Int = 7) -> [DailyTokenUsage] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"

        var results: [DailyTokenUsage] = []
        for offset in 0..<days {
            guard let date = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            let dateStr = fmt.string(from: date)
            let records = ReasonixStatsLoader.loadDay(statsDir: statsDir, date: dateStr)
            var total = 0, prompt = 0, completion = 0
            for r in records where !r.isTurn {
                total += r.totalTokens
                prompt += r.promptTokens
                completion += r.completionTokens
            }
            results.append(DailyTokenUsage(
                date: dateStr,
                totalTokens: total,
                promptTokens: prompt,
                completionTokens: completion,
                cost: 0
            ))
        }
        return results.reversed()
    }

    // MARK: - AI 分析：工具调用排行

    /// 工具调用排行（按次数、成功率、平均耗时）
    public func fetchToolCallRanking(limit: Int = 5) -> [ToolCallStats] {
        let sql = """
            SELECT tool_name,
                   COUNT(*) AS call_count,
                   SUM(CASE WHEN status = 'success' THEN 1 ELSE 0 END) AS success_count,
                   SUM(CASE WHEN status = 'failure' THEN 1 ELSE 0 END) AS fail_count,
                   ROUND(AVG(duration_ms)) AS avg_duration
            FROM hook_tool_calls
            WHERE status != 'started'
              -- 只统计近 30 天，避免全表扫描（走 idx_hook_calls_day 表达式索引）
              AND date(started_at, 'localtime') >= date('now', 'localtime', '-30 days')
            GROUP BY tool_name
            ORDER BY call_count DESC
            LIMIT \(limit)
            """
        var results: [ToolCallStats] = []
        database.query(sql: sql) { stmt in
            let name = String(cString: sqlite3_column_text(stmt, 0))
            let total = Int(sqlite3_column_int(stmt, 1))
            let success = Int(sqlite3_column_int(stmt, 2))
            let fail = Int(sqlite3_column_int(stmt, 3))
            let avgMs = Int(sqlite3_column_int(stmt, 4))
            let rate = total > 0 ? (Double(success) / Double(total)) * 100 : 0
            results.append(ToolCallStats(
                toolName: name, callCount: total,
                successCount: success, failCount: fail,
                successRate: rate, avgDurationMs: avgMs
            ))
        }
        return results
    }

    // MARK: - AI 分析：最近工具调用

    /// 最近工具调用动态
    public func fetchRecentToolCalls(limit: Int = 5) -> [RecentToolCall] {
        let sql = """
            SELECT tool_name, status, COALESCE(duration_ms, 0) AS duration_ms,
                   started_at
            FROM hook_tool_calls
            ORDER BY started_at DESC
            LIMIT \(limit)
            """
        let now = Date()
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var results: [RecentToolCall] = []
        database.query(sql: sql) { stmt in
            let name = String(cString: sqlite3_column_text(stmt, 0))
            let status = String(cString: sqlite3_column_text(stmt, 1))
            let dur = Int(sqlite3_column_int(stmt, 2))
            let tsStr = String(cString: sqlite3_column_text(stmt, 3))
            let secondsAgo: Int
            if let ts = fmt.date(from: tsStr) {
                secondsAgo = Int(now.timeIntervalSince(ts))
            } else {
                secondsAgo = 0
            }
            results.append(RecentToolCall(
                toolName: name, status: status,
                durationMs: dur, secondsAgo: secondsAgo,
                sessionId: ""
            ))
        }
        return results
    }

    // MARK: - AI 分析：模型用量排行

    /// 模型用量排行（token 来自 stats 今日文件，花费来自今日 hook 会话）
    public func fetchModelRanking(limit: Int = 5) -> [ModelRanking] {
        let today = todayDateString()
        let records = ReasonixStatsLoader.loadDay(statsDir: statsDir, date: today)
        let byModel = ReasonixStatsLoader.totalsByModel(records).prefix(limit)

        // 花费按模型聚合（hook_sessions per-session 累计 cost，本地日期）
        let costSQL = """
            SELECT COALESCE(model, '未知'),
                   COALESCE(SUM(total_cost), 0.0),
                   COUNT(*)
            FROM hook_sessions
            WHERE date(started_at, 'localtime') = '\(today)'
            GROUP BY model
            """
        var costByModel: [String: (cost: Double, count: Int)] = [:]
        database.query(sql: costSQL) { stmt in
            let model = String(cString: sqlite3_column_text(stmt, 0))
            let cost = sqlite3_column_double(stmt, 1)
            let count = Int(sqlite3_column_int(stmt, 2))
            costByModel[model] = (cost, count)
        }

        var results: [ModelRanking] = []
        for m in byModel {
            let extra = costByModel[m.model] ?? (0, 0)
            results.append(ModelRanking(
                model: m.model, totalTokens: m.total,
                totalCost: extra.cost, sessionCount: extra.count
            ))
        }
        return results
    }

    // MARK: - AI 分析：项目用量排行

    /// 项目用量排行（hook_sessions 维度，本地日期，无时区偏移）
    public func fetchProjectRanking(limit: Int = 5) -> [ProjectRanking] {
        let today = todayDateString()
        let sql = """
            SELECT COALESCE(project, '未知'),
                   COALESCE(SUM(total_tokens), 0),
                   COUNT(*) AS session_count,
                   COALESCE(SUM(total_cost), 0.0)
            FROM hook_sessions
            WHERE date(started_at, 'localtime') = '\(today)'
            GROUP BY project
            ORDER BY SUM(total_tokens) DESC
            LIMIT \(limit)
            """
        var results: [ProjectRanking] = []
        database.query(sql: sql) { stmt in
            let project = String(cString: sqlite3_column_text(stmt, 0))
            let tokens = Int(sqlite3_column_int(stmt, 1))
            let count = Int(sqlite3_column_int(stmt, 2))
            let cost = sqlite3_column_double(stmt, 3)
            results.append(ProjectRanking(
                project: project, totalTokens: tokens,
                sessionCount: count, totalCost: cost
            ))
        }
        return results
    }

    // MARK: - AI 分析：会话统计概览

    /// 会话统计概览（活跃数、失败率、推理占比）
    public func fetchSessionOverviewStats() -> SessionOverviewStats {
        let today = todayDateString()

        // 活跃会话数
        let activeSQL = "SELECT COUNT(*) FROM hook_sessions WHERE status = 'active'"
        var activeCount = 0
        database.query(sql: activeSQL) { stmt in
            activeCount = Int(sqlite3_column_int(stmt, 0))
        }

        // 今日总会话和失败数（本地日期）
        let todaySQL = """
            SELECT COUNT(*),
                   SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END)
            FROM hook_sessions
            WHERE date(started_at, 'localtime') = '\(today)'
            """
        var todayTotal = 0, todayFailed = 0
        database.query(sql: todaySQL) { stmt in
            todayTotal = Int(sqlite3_column_int(stmt, 0))
            todayFailed = Int(sqlite3_column_int(stmt, 1))
        }

        // 推理 Token 占比（stats 今日文件，reasoning/total）
        var reasoningTokens = 0, totalTokens = 0
        for r in ReasonixStatsLoader.loadDay(statsDir: statsDir, date: today) where !r.isTurn {
            reasoningTokens += r.reasoningTokens
            totalTokens += r.totalTokens
        }
        let ratio = totalTokens > 0 ? (Double(reasoningTokens) / Double(totalTokens)) * 100 : 0
        let failRate = todayTotal > 0 ? (Double(todayFailed) / Double(todayTotal)) * 100 : 0

        return SessionOverviewStats(
            activeSessions: activeCount,
            todayTotal: todayTotal,
            todayFailed: todayFailed,
            failRate: failRate,
            reasoningTokenRatio: ratio
        )
    }

    // MARK: - 辅助

    /// 获取今天的日期字符串 "yyyy-MM-dd"（本地日期）
    private func todayDateString() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }
}

// MARK: - Date 辅助

extension Date {
    /// 本地日期字符串 "yyyy-MM-dd"
    func ymdString() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: self)
    }
}
