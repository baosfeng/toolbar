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

// MARK: - Token 用量查询器

/// Token 用量统计查询器
public final class TokenUsageProvider {

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
                WHERE started_at IS NOT NULL
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

    // MARK: - 辅助

    /// 获取今天的日期字符串 "yyyy-MM-dd"
    private func todayDateString() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }
}
