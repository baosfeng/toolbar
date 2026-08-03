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

/// Token 用量统计查询器
public final class TokenUsageProvider: TokenStatsService {

    private let database: DatabaseManager

    public init(database: DatabaseManager) {
        self.database = database
    }

    // MARK: - 今日汇总

    /// 查询今日 token 用量汇总（按模型分组）
    public func fetchTodaySummary() -> TodayTokenSummary {
        let today = todayDateString()

        var byModel: [TokenUsageByModel] = []
        var grandTotalTokens = 0
        var grandTotalCost = 0.0

        let sql = """
            SELECT COALESCE(s.model, '未知'),
                   COALESCE(SUM(s.prompt_tokens), 0),
                   COALESCE(SUM(s.completion_tokens), 0),
                   COALESCE(SUM(s.total_tokens), 0),
                   COALESCE(SUM(s.cost), 0.0)
            FROM (
                SELECT session_id, model,
                       MAX(prompt_tokens) AS prompt_tokens,
                       MAX(completion_tokens) AS completion_tokens,
                       MAX(total_tokens) AS total_tokens,
                       MAX(cost) AS cost
                FROM hook_events
                WHERE date(timestamp, '+8 hours') = '\(today)'
                GROUP BY session_id
            ) s
            GROUP BY s.model
            ORDER BY SUM(s.total_tokens) DESC
            """

        database.query(sql: sql) { stmt in
            let model = String(cString: sqlite3_column_text(stmt, 0))
            let prompt = Int(sqlite3_column_int(stmt, 1))
            let completion = Int(sqlite3_column_int(stmt, 2))
            let total = Int(sqlite3_column_int(stmt, 3))
            let cost = sqlite3_column_double(stmt, 4)

            byModel.append(TokenUsageByModel(
                model: model,
                promptTokens: prompt,
                completionTokens: completion,
                totalTokens: total,
                cost: cost
            ))
            grandTotalTokens += total
            grandTotalCost += cost
        }

        return TodayTokenSummary(
            totalTokens: grandTotalTokens,
            totalCost: grandTotalCost,
            byModel: byModel
        )
    }

    /// 今日总计（快速查询，无需分组）
    public func fetchTodayTotal() -> (tokens: Int, cost: Double) {
        let today = todayDateString()

        let sql = """
            SELECT COALESCE(SUM(total_tokens), 0),
                   COALESCE(SUM(total_cost), 0.0)
            FROM hook_sessions
            WHERE date(started_at, '+8 hours') = '\(today)'
            """

        var tokens = 0
        var cost = 0.0
        database.query(sql: sql) { stmt in
            tokens = Int(sqlite3_column_int(stmt, 0))
            cost = sqlite3_column_double(stmt, 1)
        }
        return (tokens, cost)
    }

    // MARK: - 每小时明细

    /// 查询指定日期的每小时 token 用量明细
    /// - Parameter dateString: "2026-07-25" 格式，传 nil 则查今天
    public func fetchHourlyBreakdown(dateString: String? = nil) -> [HourlyTokenUsage] {
        let day = dateString ?? todayDateString()

        let sql = """
            SELECT s.hour,
                   COALESCE(SUM(s.prompt_tokens), 0),
                   COALESCE(SUM(s.completion_tokens), 0),
                   COALESCE(SUM(s.total_tokens), 0),
                   COALESCE(SUM(s.cost), 0.0)
            FROM (
                SELECT CAST(strftime('%H', MAX(timestamp), '+8 hours') AS INTEGER) AS hour,
                       MAX(prompt_tokens) AS prompt_tokens,
                       MAX(completion_tokens) AS completion_tokens,
                       MAX(total_tokens) AS total_tokens,
                       MAX(cost) AS cost
                FROM hook_events
                WHERE date(timestamp, '+8 hours') = '\(day)'
                GROUP BY session_id
            ) s
            GROUP BY s.hour
            ORDER BY s.hour
            """

        var results: [HourlyTokenUsage] = []
        database.query(sql: sql) { stmt in
            let hour = Int(sqlite3_column_int(stmt, 0))
            let prompt = Int(sqlite3_column_int(stmt, 1))
            let completion = Int(sqlite3_column_int(stmt, 2))
            let total = Int(sqlite3_column_int(stmt, 3))
            let cost = sqlite3_column_double(stmt, 4)
            results.append(HourlyTokenUsage(
                hour: hour,
                promptTokens: prompt,
                completionTokens: completion,
                totalTokens: total,
                cost: cost
            ))
        }

        // 补全 0–23 小时，无数据的小时填 0
        var filled: [HourlyTokenUsage] = []
        for hour in 0..<24 {
            if let existing = results.first(where: { $0.hour == hour }) {
                filled.append(existing)
            } else {
                filled.append(HourlyTokenUsage(hour: hour, promptTokens: 0, completionTokens: 0, totalTokens: 0, cost: 0))
            }
        }
        return filled
    }

    // MARK: - 每日历史

    /// 查询最近 N 天的每日汇总
    public func fetchDailyHistory(days: Int = 7) -> [DailyTokenUsage] {

        let sql = """
            SELECT s.day,
                   COALESCE(SUM(s.prompt_tokens), 0),
                   COALESCE(SUM(s.completion_tokens), 0),
                   COALESCE(SUM(s.total_tokens), 0),
                   COALESCE(SUM(s.cost), 0.0)
            FROM (
                SELECT date(started_at, '+8 hours') AS day,
                       total_prompt_tokens AS prompt_tokens,
                       total_completion_tokens AS completion_tokens,
                       total_tokens,
                       total_cost AS cost
                FROM hook_sessions
                -- 只统计近 14 天，避免全表扫描（走 idx_hook_sessions_day 表达式索引）
                WHERE date(started_at, '+8 hours') >= date('now', 'localtime', '-14 days')
            ) s
            GROUP BY s.day
            ORDER BY s.day DESC
            LIMIT \(days)
            """

        var results: [DailyTokenUsage] = []
        database.query(sql: sql) { stmt in
            let dateStr = String(cString: sqlite3_column_text(stmt, 0))
            let prompt = Int(sqlite3_column_int(stmt, 1))
            let completion = Int(sqlite3_column_int(stmt, 2))
            let total = Int(sqlite3_column_int(stmt, 3))
            let cost = sqlite3_column_double(stmt, 4)
            results.append(DailyTokenUsage(
                date: dateStr,
                totalTokens: total,
                promptTokens: prompt,
                completionTokens: completion,
                cost: cost
            ))
        }

        // 补全连续 7 天，无数据的天填 0
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        var filled: [DailyTokenUsage] = []
        for offset in 0..<days {
            guard let date = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            let dateStr = fmt.string(from: date)
            if let existing = results.first(where: { $0.date == dateStr }) {
                filled.append(existing)
            } else {
                filled.append(DailyTokenUsage(date: dateStr, totalTokens: 0, promptTokens: 0, completionTokens: 0, cost: 0))
            }
        }
        return filled.reversed()
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
              AND date(started_at, '+8 hours') >= date('now', 'localtime', '-30 days')
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

    /// 模型用量排行
    public func fetchModelRanking(limit: Int = 5) -> [ModelRanking] {
        let today = todayDateString()
        let sql = """
            SELECT COALESCE(model, '未知'),
                   COALESCE(SUM(total_tokens), 0),
                   COALESCE(SUM(total_cost), 0.0),
                   COUNT(*) AS session_count
            FROM hook_sessions
            WHERE date(started_at, '+8 hours') = '\(today)'
            GROUP BY model
            ORDER BY SUM(total_tokens) DESC
            LIMIT \(limit)
            """
        var results: [ModelRanking] = []
        database.query(sql: sql) { stmt in
            let model = String(cString: sqlite3_column_text(stmt, 0))
            let tokens = Int(sqlite3_column_int(stmt, 1))
            let cost = sqlite3_column_double(stmt, 2)
            let count = Int(sqlite3_column_int(stmt, 3))
            results.append(ModelRanking(
                model: model, totalTokens: tokens,
                totalCost: cost, sessionCount: count
            ))
        }
        return results
    }

    // MARK: - AI 分析：项目用量排行

    /// 项目用量排行
    public func fetchProjectRanking(limit: Int = 5) -> [ProjectRanking] {
        let today = todayDateString()
        let sql = """
            SELECT COALESCE(project, '未知'),
                   COALESCE(SUM(total_tokens), 0),
                   COUNT(*) AS session_count,
                   COALESCE(SUM(total_cost), 0.0)
            FROM hook_sessions
            WHERE date(started_at, '+8 hours') = '\(today)'
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

        // 今日总会话和失败数
        let todaySQL = """
            SELECT COUNT(*),
                   SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END)
            FROM hook_sessions
            WHERE date(started_at, '+8 hours') = '\(today)'
            """
        var todayTotal = 0, todayFailed = 0
        database.query(sql: todaySQL) { stmt in
            todayTotal = Int(sqlite3_column_int(stmt, 0))
            todayFailed = Int(sqlite3_column_int(stmt, 1))
        }

        // 推理 Token 占比
        let ratioSQL = """
            SELECT COALESCE(SUM(total_reasoning_tokens), 0),
                   COALESCE(SUM(total_tokens), 0)
            FROM hook_sessions
            WHERE date(started_at, '+8 hours') = '\(today)'
              AND total_tokens > 0
            """
        var reasoningTokens = 0, totalTokens = 0
        database.query(sql: ratioSQL) { stmt in
            reasoningTokens = Int(sqlite3_column_int(stmt, 0))
            totalTokens = Int(sqlite3_column_int(stmt, 1))
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

    /// 获取今天的日期字符串 "yyyy-MM-dd"
    private func todayDateString() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }
}
