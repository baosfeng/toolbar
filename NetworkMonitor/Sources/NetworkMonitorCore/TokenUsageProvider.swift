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
            SELECT COALESCE(model, '未知'),
                   COALESCE(SUM(prompt_tokens), 0),
                   COALESCE(SUM(completion_tokens), 0),
                   COALESCE(SUM(total_tokens), 0),
                   COALESCE(SUM(cost), 0.0)
            FROM hook_events
            WHERE date(timestamp) = '\(today)'
            GROUP BY model
            ORDER BY SUM(total_tokens) DESC
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
                   COALESCE(SUM(cost), 0.0)
            FROM hook_events
            WHERE date(timestamp) = '\(today)'
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
            SELECT CAST(strftime('%H', timestamp) AS INTEGER) AS hour,
                   COALESCE(SUM(prompt_tokens), 0),
                   COALESCE(SUM(completion_tokens), 0),
                   COALESCE(SUM(total_tokens), 0),
                   COALESCE(SUM(cost), 0.0)
            FROM hook_events
            WHERE date(timestamp) = '\(day)'
            GROUP BY hour
            ORDER BY hour
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

        return results
    }

    // MARK: - 每日历史

    /// 查询最近 N 天的每日汇总
    public func fetchDailyHistory(days: Int = 7) -> [DailyTokenUsage] {
        let today = todayDateString()

        let sql = """
            SELECT date(timestamp) AS day,
                   COALESCE(SUM(prompt_tokens), 0),
                   COALESCE(SUM(completion_tokens), 0),
                   COALESCE(SUM(total_tokens), 0),
                   COALESCE(SUM(cost), 0.0)
            FROM hook_events
            WHERE date(timestamp) <= '\(today)'
            GROUP BY day
            ORDER BY day DESC
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

        return results
    }

    // MARK: - 辅助

    /// 获取今天的日期字符串 "yyyy-MM-dd"
    private func todayDateString() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }
}
