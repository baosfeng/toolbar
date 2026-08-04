import Foundation
import SQLite3

// MARK: - Hook 事件仓储实现

/// `DatabaseManager` 的 Hook 事件仓储实现（接口隔离：见 `HookEventRepository`）
extension DatabaseManager: HookEventRepository {

    /// 写入一条 Hook 事件记录
    public func writeHookEvent(event: ReasonixHookEvent) {
        let sql = """
        INSERT INTO hook_events
            (event_type, event_type_cn, session_id, project, model, topic, turns,
             prompt_tokens, completion_tokens, total_tokens, reasoning_tokens, cost,
             event_data_json, timestamp, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        let now = ISO8601DateFormatter().string(from: Date())

        serialQueue.async { [weak self] in
            guard let db = self?.db else { return }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                self?.logger.warning("hook_events 写入准备失败: \(String(cString: sqlite3_errmsg(db)))")
                return
            }

            sqlite3_bind_text(stmt, 1, (event.eventType.rawValue as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (event.eventTypeCN as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 3, (event.sessionId as NSString).utf8String, -1, nil)
            self?.sqlite3_bind_text_or_null(stmt, 4, event.project)
            self?.sqlite3_bind_text_or_null(stmt, 5, event.model)
            self?.sqlite3_bind_text_or_null(stmt, 6, event.topic)
            sqlite3_bind_int(stmt, 7, Int32(event.turns))
            sqlite3_bind_int(stmt, 8, Int32(event.promptTokens))
            sqlite3_bind_int(stmt, 9, Int32(event.completionTokens))
            sqlite3_bind_int(stmt, 10, Int32(event.totalTokens))
            sqlite3_bind_int(stmt, 11, Int32(event.reasoningTokens))
            sqlite3_bind_double(stmt, 12, event.cost)
            self?.sqlite3_bind_text_or_null(stmt, 13, event.eventDataJSON)
            sqlite3_bind_text(stmt, 14, (event.timestamp as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 15, (now as NSString).utf8String, -1, nil)

            if sqlite3_step(stmt) != SQLITE_DONE {
                self?.logger.warning("hook_events 写入失败: \(String(cString: sqlite3_errmsg(db)))")
            }
        }
    }

    /// 创建或更新会话汇总记录
    public func upsertHookSession(event: ReasonixHookEvent) {
        let now = ISO8601DateFormatter().string(from: Date())

        serialQueue.async { [weak self] in
            guard let db = self?.db else { return }

            // 先查是否存在
            let selectSQL = "SELECT status, total_turns, total_prompt_tokens, total_completion_tokens, total_tokens, total_reasoning_tokens, total_cost FROM hook_sessions WHERE session_id = ?;"
            var selectStmt: OpaquePointer?
            defer { sqlite3_finalize(selectStmt) }

            guard sqlite3_prepare_v2(db, selectSQL, -1, &selectStmt, nil) == SQLITE_OK else { return }
            sqlite3_bind_text(selectStmt, 1, (event.sessionId as NSString).utf8String, -1, nil)

            let exists = sqlite3_step(selectStmt) == SQLITE_ROW

            if exists {
                let oldTurns = Int(sqlite3_column_int(selectStmt, 1))
                let oldPrompt = Int(sqlite3_column_int(selectStmt, 2))
                let oldCompletion = Int(sqlite3_column_int(selectStmt, 3))
                let oldTotal = Int(sqlite3_column_int(selectStmt, 4))
                let oldReasoning = Int(sqlite3_column_int(selectStmt, 5))
                let oldCost = sqlite3_column_double(selectStmt, 6)
                let oldStatus = String(cString: sqlite3_column_text(selectStmt, 0))

                let isEnd = event.isSessionEnd
                let isFailed = event.isStopFailure

                // 取最大值 — 每个 Stop/SessionEnd 携带累积值，非增量
                let newTurns = max(oldTurns, event.turns)
                let newPrompt = max(oldPrompt, event.promptTokens)
                let newCompletion = max(oldCompletion, event.completionTokens)
                let newTotal = max(oldTotal, event.totalTokens)
                let newReasoning = max(oldReasoning, event.reasoningTokens)
                let newCost = max(oldCost, event.cost)
                // 状态机：SessionEnd → ended；StopFailure → failed（除非已 ended）；否则保持
                let newStatus: String
                if isEnd {
                    newStatus = "'ended'"
                } else if isFailed, oldStatus != "ended" {
                    newStatus = "'failed'"
                } else {
                    newStatus = "'\(oldStatus)'"
                }
                let endedSQL = isEnd ? ", ended_at = '\(event.timestamp)'" : ""

                let updateSQL = """
                UPDATE hook_sessions SET
                    total_turns = \(newTurns),
                    total_prompt_tokens = \(newPrompt),
                    total_completion_tokens = \(newCompletion),
                    total_tokens = \(newTotal),
                    total_reasoning_tokens = \(newReasoning),
                    total_cost = \(newCost),
                    status = \(newStatus),
                    updated_at = '\(now)'
                    \(endedSQL)
                WHERE session_id = '\(event.sessionId.replacingOccurrences(of: "'", with: "''"))';
                """

                var updateStmt: OpaquePointer?
                defer { sqlite3_finalize(updateStmt) }

                guard sqlite3_prepare_v2(db, updateSQL, -1, &updateStmt, nil) == SQLITE_OK,
                      sqlite3_step(updateStmt) == SQLITE_DONE else {
                    self?.logger.warning("hook_sessions 更新失败: \(String(cString: sqlite3_errmsg(db)))")
                    return
                }
            } else {
                // 新建记录
                let startedAt = event.isSessionStart ? event.timestamp : event.timestamp
                let isEnd = event.isSessionEnd
                let isFailed = event.isStopFailure

                let insertSQL = """
                INSERT INTO hook_sessions
                    (session_id, project, model, topic, started_at, ended_at,
                     total_turns, total_prompt_tokens, total_completion_tokens,
                     total_tokens, total_reasoning_tokens, total_cost, status, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                """

                var insertStmt: OpaquePointer?
                defer { sqlite3_finalize(insertStmt) }

                guard sqlite3_prepare_v2(db, insertSQL, -1, &insertStmt, nil) == SQLITE_OK else {
                    self?.logger.warning("hook_sessions 插入准备失败: \(String(cString: sqlite3_errmsg(db)))")
                    return
                }

                sqlite3_bind_text(insertStmt, 1, (event.sessionId as NSString).utf8String, -1, nil)
                self?.sqlite3_bind_text_or_null(insertStmt, 2, event.project)
                self?.sqlite3_bind_text_or_null(insertStmt, 3, event.model)
                self?.sqlite3_bind_text_or_null(insertStmt, 4, event.topic)
                sqlite3_bind_text(insertStmt, 5, (startedAt as NSString).utf8String, -1, nil)
                if isEnd {
                    sqlite3_bind_text(insertStmt, 6, (event.timestamp as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(insertStmt, 6)
                }
                sqlite3_bind_int(insertStmt, 7, Int32(event.turns))
                sqlite3_bind_int(insertStmt, 8, Int32(event.promptTokens))
                sqlite3_bind_int(insertStmt, 9, Int32(event.completionTokens))
                sqlite3_bind_int(insertStmt, 10, Int32(event.totalTokens))
                sqlite3_bind_int(insertStmt, 11, Int32(event.reasoningTokens))
                sqlite3_bind_double(insertStmt, 12, event.cost)
                sqlite3_bind_text(insertStmt, 13, ((isEnd ? "ended" : (isFailed ? "failed" : "active")) as NSString).utf8String, -1, nil)
                sqlite3_bind_text(insertStmt, 14, (now as NSString).utf8String, -1, nil)

                if sqlite3_step(insertStmt) != SQLITE_DONE {
                    self?.logger.warning("hook_sessions 插入失败: \(String(cString: sqlite3_errmsg(db)))")
                }
            }
        }
    }

    /// 创建工具调用记录（PreToolUse 时调用）
    public func startHookToolCall(sessionId: String, turn: Int, toolName: String, toolArgsJSON: String?, timestamp: String) {
        let sql = """
        INSERT INTO hook_tool_calls
            (session_id, turn, tool_name, tool_args_json, status, started_at)
        VALUES (?, ?, ?, ?, 'started', ?);
        """

        serialQueue.async { [weak self] in
            guard let db = self?.db else { return }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                self?.logger.warning("hook_tool_calls 写入准备失败: \(String(cString: sqlite3_errmsg(db)))")
                return
            }

            sqlite3_bind_text(stmt, 1, (sessionId as NSString).utf8String, -1, nil)
            sqlite3_bind_int(stmt, 2, Int32(turn))
            sqlite3_bind_text(stmt, 3, (toolName as NSString).utf8String, -1, nil)
            self?.sqlite3_bind_text_or_null(stmt, 4, toolArgsJSON)
            sqlite3_bind_text(stmt, 5, (timestamp as NSString).utf8String, -1, nil)

            if sqlite3_step(stmt) != SQLITE_DONE {
                self?.logger.warning("hook_tool_calls 写入失败: \(String(cString: sqlite3_errmsg(db)))")
            }
        }
    }

    /// 更新工具调用记录（PostToolUse / PostToolUseFailure 时调用）
    public func finishHookToolCall(sessionId: String, turn: Int, toolName: String, status: String, resultPreview: String?, error: String?, timestamp: String) {
        let sql = """
        UPDATE hook_tool_calls
        SET status = ?,
            result_preview = ?,
            error = ?,
            completed_at = ?,
            duration_ms = (
                SELECT ROUND((julianday(?) - julianday(started_at)) * 86400000)
                FROM hook_tool_calls
                WHERE session_id = ? AND turn = ? AND tool_name = ?
                  AND id = (SELECT MAX(id) FROM hook_tool_calls WHERE session_id = ? AND turn = ? AND tool_name = ?)
            )
        WHERE session_id = ? AND turn = ? AND tool_name = ?
          AND id = (SELECT MAX(id) FROM hook_tool_calls WHERE session_id = ? AND turn = ? AND tool_name = ?);
        """

        serialQueue.async { [weak self] in
            guard let db = self?.db else { return }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                self?.logger.warning("hook_tool_calls 更新准备失败: \(String(cString: sqlite3_errmsg(db)))")
                return
            }

            sqlite3_bind_text(stmt, 1, (status as NSString).utf8String, -1, nil)
            self?.sqlite3_bind_text_or_null(stmt, 2, resultPreview)
            self?.sqlite3_bind_text_or_null(stmt, 3, error)
            sqlite3_bind_text(stmt, 4, (timestamp as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 5, (timestamp as NSString).utf8String, -1, nil)

            // 10 个 session_id/turn/tool_name 绑定
            let sessionCStr = (sessionId as NSString).utf8String
            for i in stride(from: 6, through: 15, by: 3) {
                sqlite3_bind_text(stmt, Int32(i), sessionCStr, -1, nil)
                sqlite3_bind_int(stmt, Int32(i + 1), Int32(turn))
                sqlite3_bind_text(stmt, Int32(i + 2), (toolName as NSString).utf8String, -1, nil)
            }

            if sqlite3_step(stmt) != SQLITE_DONE {
                self?.logger.warning("hook_tool_calls 更新失败: \(String(cString: sqlite3_errmsg(db)))")
            }
        }
    }

    /// 查询当前活跃会话概览
    public func queryActiveSessions(limit: Int = 5) -> [[String: Any]] {
        var results: [[String: Any]] = []
        serialQueue.sync {
            guard let db else { return }

            let sql = "SELECT * FROM hook_sessions WHERE status = 'active' ORDER BY updated_at DESC LIMIT \(limit);"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }

            while sqlite3_step(stmt) == SQLITE_ROW {
                var row: [String: Any] = [:]
                let colCount = sqlite3_column_count(stmt)
                for i in 0..<colCount {
                    let colName = String(cString: sqlite3_column_name(stmt, i))
                    switch sqlite3_column_type(stmt, i) {
                    case SQLITE_INTEGER:
                        row[colName] = Int(sqlite3_column_int(stmt, i))
                    case SQLITE_FLOAT:
                        row[colName] = sqlite3_column_double(stmt, i)
                    case SQLITE_TEXT:
                        if let text = sqlite3_column_text(stmt, i) {
                            row[colName] = String(cString: text)
                        }
                    case SQLITE_NULL:
                        row[colName] = NSNull()
                    default:
                        break
                    }
                }
                results.append(row)
            }
        }
        return results
    }

    /// 查询指定会话的最近工具调用
    public func queryToolCalls(sessionId: String, limit: Int = 20) -> [[String: Any]] {
        var results: [[String: Any]] = []
        let safeId = sessionId.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." }
        let safeLimit = min(max(limit, 1), 1000)

        serialQueue.sync {
            guard let db else { return }

            let sql = "SELECT * FROM hook_tool_calls WHERE session_id = ? ORDER BY id DESC LIMIT ?;"
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }

            sqlite3_bind_text(stmt, 1, (safeId as NSString).utf8String, -1, nil)
            sqlite3_bind_int(stmt, 2, Int32(safeLimit))

            while sqlite3_step(stmt) == SQLITE_ROW {
                var row: [String: Any] = [:]
                let colCount = sqlite3_column_count(stmt)
                for i in 0..<colCount {
                    let colName = String(cString: sqlite3_column_name(stmt, i))
                    switch sqlite3_column_type(stmt, i) {
                    case SQLITE_INTEGER:
                        row[colName] = Int(sqlite3_column_int(stmt, i))
                    case SQLITE_FLOAT:
                        row[colName] = sqlite3_column_double(stmt, i)
                    case SQLITE_TEXT:
                        if let text = sqlite3_column_text(stmt, i) {
                            row[colName] = String(cString: text)
                        }
                    case SQLITE_NULL:
                        row[colName] = NSNull()
                    default:
                        break
                    }
                }
                results.append(row)
            }
        }
        return results
    }
}
