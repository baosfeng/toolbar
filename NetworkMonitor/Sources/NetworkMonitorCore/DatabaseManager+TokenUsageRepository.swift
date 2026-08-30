import Foundation
import SQLite3

// MARK: - Token 用量仓储实现

/// `DatabaseManager` 的 Token 用量仓储实现（接口隔离：见 `TokenUsageRepository`）
extension DatabaseManager: TokenUsageRepository {

    /// 插入一条 token 用量记录（幂等：UNIQUE 冲突时自动忽略，重复导入安全）
    public func insertTokenUsage(source: String, date: String, hour: Int, record: ReasonixStatsRecord) {
        insertTokenUsages(source: source, date: date, entries: [(hour, record)])
    }

    /// 批量插入 token 用量记录（单事务提交，幂等：UNIQUE 冲突自动忽略）
    /// 逐条插入时每条都是独立事务，WAL 模式下会产生大量 fsync；批量导入用单事务大幅减少 I/O。
    public func insertTokenUsages(source: String, date: String, entries: [(hour: Int, record: ReasonixStatsRecord)]) {
        guard !entries.isEmpty else { return }
        let sql = """
        INSERT OR IGNORE INTO token_usage
            (source, date, hour, ts, model,
             prompt_tokens, completion_tokens, reasoning_tokens,
             cache_hit_tokens, cache_miss_tokens, total_tokens, is_turn)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        serialQueue.async { [weak self] in
            guard let self, let db = self.db else { return }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                self.logger.warning("token_usage 批量写入准备失败: \(String(cString: sqlite3_errmsg(db)))")
                return
            }

            // 单事务包裹：任一绑定/执行失败则整体回滚（保证幂等状态一致）
            if sqlite3_exec(db, "BEGIN", nil, nil, nil) != SQLITE_OK {
                self.logger.warning("token_usage 事务开启失败: \(String(cString: sqlite3_errmsg(db)))")
                return
            }

            var failed = false
            var stepError = ""
            for (hour, record) in entries {
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)
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
                    failed = true
                    stepError = String(cString: sqlite3_errmsg(db))
                    break
                }
            }

            let finalizeSQL = failed ? "ROLLBACK" : "COMMIT"
            if sqlite3_exec(db, finalizeSQL, nil, nil, nil) != SQLITE_OK {
                self.logger.warning("token_usage 事务\(failed ? "回滚" : "提交")失败: \(String(cString: sqlite3_errmsg(db)))")
                return
            }
            if failed {
                self.logger.warning("token_usage 批量写入失败，已回滚: \(stepError)")
            }
        }
    }
}
