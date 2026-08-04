import Foundation
import SQLite3

// MARK: - Token 用量仓储实现

/// `DatabaseManager` 的 Token 用量仓储实现（接口隔离：见 `TokenUsageRepository`）
extension DatabaseManager: TokenUsageRepository {

    /// 插入一条 token 用量记录（幂等：UNIQUE 冲突时自动忽略，重复导入安全）
    public func insertTokenUsage(source: String, date: String, hour: Int, record: ReasonixStatsRecord) {
        let sql = """
        INSERT OR IGNORE INTO token_usage
            (source, date, hour, ts, model,
             prompt_tokens, completion_tokens, reasoning_tokens,
             cache_hit_tokens, cache_miss_tokens, total_tokens, is_turn)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        serialQueue.async { [weak self] in
            guard let db = self?.db else { return }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                print("⚠️ token_usage 写入准备失败: \(String(cString: sqlite3_errmsg(db)))")
                return
            }

            sqlite3_bind_text(stmt, 1, (source as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (date as NSString).utf8String, -1, nil)
            sqlite3_bind_int(stmt, 3, Int32(hour))
            sqlite3_bind_text(stmt, 4, (record.ts as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 5, (record.model as NSString).utf8String, -1, nil)
            sqlite3_bind_int(stmt, 6, Int32(record.promptTokens))
            sqlite3_bind_int(stmt, 7, Int32(record.completionTokens))
            sqlite3_bind_int(stmt, 8, Int32(record.reasoningTokens))
            sqlite3_bind_int(stmt, 9, Int32(record.cacheHitTokens))
            sqlite3_bind_int(stmt, 10, Int32(record.cacheMissTokens))
            sqlite3_bind_int(stmt, 11, Int32(record.totalTokens))
            sqlite3_bind_int(stmt, 12, record.isTurn ? 1 : 0)

            if sqlite3_step(stmt) != SQLITE_DONE {
                print("⚠️ token_usage 写入失败: \(String(cString: sqlite3_errmsg(db)))")
            }
        }
    }
}
