import Foundation
import SQLite3

// MARK: - 建表与历史表结构

/// 说明：与主文件同属 `DatabaseManager`，成员可见性放宽为 internal 以便跨文件调用。
extension DatabaseManager {

    // MARK: - 建表

    /// 创建所有需要的表（仅首次运行时执行）
    func createTables() {
        // 历史表（AI 助手事件 / token 统计）：表为历史数据保留，代码已不再使用
        createLegacyTables()

        createIndexes()
    }

    /// 创建索引以优化查询性能
    private func createIndexes() {
        // 历史表索引（同上，仅保留既有数据结构）
        createLegacyIndexes()
    }

    // MARK: - 历史表创建（保留）

    /// 创建历史事件与用量相关表
    ///
    /// 说明：AI 助手与 token 统计链路已整体移除，建表与索引语句保留仅为兼容既有用户数据，
    /// 不做删表迁移（删表有损坏用户数据的风险）。
    private func createLegacyTables() {
        let legacyStatements = [
            // 事件流水表
            """
            CREATE TABLE IF NOT EXISTS hook_events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                event_type TEXT NOT NULL,
                event_type_cn TEXT NOT NULL,
                session_id TEXT NOT NULL,
                project TEXT,
                model TEXT,
                topic TEXT,
                turns INTEGER DEFAULT 0,
                prompt_tokens INTEGER DEFAULT 0,
                completion_tokens INTEGER DEFAULT 0,
                total_tokens INTEGER DEFAULT 0,
                reasoning_tokens INTEGER DEFAULT 0,
                cost REAL DEFAULT 0.0,          -- 金额（CNY，USD 在写入前转换）
                event_data_json TEXT,
                timestamp TEXT NOT NULL,
                created_at TEXT NOT NULL
            );
            """,

            // 会话汇总表
            """
            CREATE TABLE IF NOT EXISTS hook_sessions (
                session_id TEXT PRIMARY KEY,
                project TEXT,
                model TEXT,
                topic TEXT,
                started_at TEXT,
                ended_at TEXT,
                total_turns INTEGER DEFAULT 0,
                total_prompt_tokens INTEGER DEFAULT 0,
                total_completion_tokens INTEGER DEFAULT 0,
                total_tokens INTEGER DEFAULT 0,
                total_reasoning_tokens INTEGER DEFAULT 0,
                total_cost REAL DEFAULT 0.0,    -- 金额（CNY，USD 在写入前转换）
                status TEXT NOT NULL DEFAULT 'active',
                updated_at TEXT NOT NULL
            );
            """,

            // 工具调用明细表
            """
            CREATE TABLE IF NOT EXISTS hook_tool_calls (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id TEXT NOT NULL,
                turn INTEGER NOT NULL,
                tool_name TEXT NOT NULL,
                tool_args_json TEXT,
                status TEXT NOT NULL DEFAULT 'started',
                result_preview TEXT,
                error TEXT,
                started_at TEXT NOT NULL,
                completed_at TEXT,
                duration_ms INTEGER
            );
            """,

            // Token 用量记录表（stats JSONL 导入，统计唯一权威数据源）
            """
            CREATE TABLE IF NOT EXISTS token_usage (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                source TEXT NOT NULL DEFAULT 'desktop',   -- 数据来源（历史字段，取值由旧版本写入）
                date TEXT NOT NULL,                       -- 本地日期 YYYY-MM-DD（stats 文件名）
                hour INTEGER NOT NULL,                    -- 本地小时 0-23（ts 解析）
                ts TEXT NOT NULL,                         -- 原始 ISO8601 时间戳（自带时区）
                model TEXT NOT NULL DEFAULT '',
                prompt_tokens INTEGER NOT NULL DEFAULT 0,
                completion_tokens INTEGER NOT NULL DEFAULT 0,
                reasoning_tokens INTEGER NOT NULL DEFAULT 0,
                cache_hit_tokens INTEGER NOT NULL DEFAULT 0,
                cache_miss_tokens INTEGER NOT NULL DEFAULT 0,
                total_tokens INTEGER NOT NULL DEFAULT 0,
                is_turn INTEGER NOT NULL DEFAULT 0,       -- 1 = TurnDone 标记行（不计入统计）
                created_at TEXT NOT NULL DEFAULT (datetime('now')),
                UNIQUE(source, date, ts, model, total_tokens)  -- 幂等：重复导入自动忽略
            );
            """,
        ]

        for sql in legacyStatements {
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            let status = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
            guard status == SQLITE_OK else {
                logger.error("历史表建表失败: \(String(cString: sqlite3_errmsg(db)))")
                return
            }

            if sqlite3_step(stmt) != SQLITE_DONE {
                logger.error("历史表建表执行失败: \(String(cString: sqlite3_errmsg(db)))")
                return
            }
        }
    }

    /// 创建历史表相关索引
    private func createLegacyIndexes() {
        // 清理旧的固定 +8 时区表达式索引（时区本地化后定义已过时，需按新时区重建）
        let legacyDrop = [
            "DROP INDEX IF EXISTS idx_hook_events_day;",
            "DROP INDEX IF EXISTS idx_hook_sessions_day;",
            "DROP INDEX IF EXISTS idx_hook_calls_day;",
        ]
        for sql in legacyDrop {
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
                  sqlite3_step(stmt) == SQLITE_DONE else {
                logger.warning("旧索引清理失败: \(String(cString: sqlite3_errmsg(db)))")
                continue
            }
        }

        // 表达式索引必须与查询中的 date(列, 偏移) 完全一致才能命中
        // 注意：SQLite 不允许在索引中使用非确定性函数（'localtime' 依赖系统时区），
        // 历史用量统计已随链路移除，因此不再创建按天表达式索引，仅保留普通索引。
        let legacyIndexes = [
            "CREATE INDEX IF NOT EXISTS idx_hook_events_session ON hook_events(session_id);",
            "CREATE INDEX IF NOT EXISTS idx_hook_events_type ON hook_events(event_type);",
            "CREATE INDEX IF NOT EXISTS idx_hook_events_time ON hook_events(timestamp);",
            "CREATE INDEX IF NOT EXISTS idx_hook_events_session_time ON hook_events(session_id, timestamp);",
            "CREATE INDEX IF NOT EXISTS idx_hook_sessions_status ON hook_sessions(status);",
            "CREATE INDEX IF NOT EXISTS idx_hook_sessions_started ON hook_sessions(started_at);",
            "CREATE INDEX IF NOT EXISTS idx_hook_calls_session ON hook_tool_calls(session_id);",
            "CREATE INDEX IF NOT EXISTS idx_hook_calls_session_turn ON hook_tool_calls(session_id, turn);",
            "CREATE INDEX IF NOT EXISTS idx_hook_calls_status ON hook_tool_calls(status);",
            "CREATE INDEX IF NOT EXISTS idx_hook_calls_started ON hook_tool_calls(started_at);",
            // 历史 token_usage 表索引（表为历史数据保留，代码已不再使用）
            "CREATE INDEX IF NOT EXISTS idx_token_usage_date ON token_usage(date, is_turn);",
            "CREATE INDEX IF NOT EXISTS idx_token_usage_date_hour ON token_usage(date, hour, is_turn);",
            "CREATE INDEX IF NOT EXISTS idx_token_usage_model ON token_usage(date, model, is_turn);",
        ]

        for sql in legacyIndexes {
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
                  sqlite3_step(stmt) == SQLITE_DONE else {
                logger.warning("历史表索引创建失败: \(String(cString: sqlite3_errmsg(db)))")
                continue
            }
        }
    }
}
