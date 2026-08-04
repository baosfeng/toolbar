import Foundation
import SQLite3

/// 数据库管理器：管理 SQLite 数据库的初始化和基本操作
/// 数据存储在 ~/Library/Application Support/macMonitor/monitor.db
///
/// 线程安全说明：
/// - 所有 sqlite3_* 调用通过串行队列 `serialQueue` 访问，保证单线程操作 db 指针
/// - `PRAGMA mmap_size=0` 禁用 mmap，避免 Apple 平台 mmap/purgeable 缓存导致的死锁
/// - `PRAGMA journal_mode=WAL` 启用 WAL 模式，读写不互相阻塞
///
/// 测试支持：
/// - `initializeInMemory()` 使用 `:memory:` 数据库，适合单元测试
public final class DatabaseManager: @unchecked Sendable, DatabaseService {

    // MARK: - 属性

    private var db: OpaquePointer?

    /// 日志服务
    public var logger: LoggingService = AppContext.shared.logger

    /// 串行队列 — 所有数据库操作在此队列上执行
    private let serialQueue = DispatchQueue(label: "com.example.NetworkMonitor.database")

    /// 过期数据清理定时器（每日一次）
    private var retentionTimer: DispatchSourceTimer?

    /// 数据库文件路径
    public private(set) lazy var dbPath: String = {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("macMonitor", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true
        )
        return dir.appendingPathComponent("monitor.db").path
    }()

    public init() {}

    // MARK: - 初始化与关闭

    /// 打开数据库并创建表结构（基于文件系统默认路径）
    public func initialize() {
        serialQueue.sync {
            _initialize()
        }
    }

    /// 打开内存数据库（仅用于测试）
    public func initializeInMemory() {
        serialQueue.sync {
            _openInMemory()
        }
    }

    private func _initialize() {
        let path = (dbPath as NSString).utf8String
        guard let cPath = path else {
            print("❌ 数据库路径无效")
            return
        }

        let status = sqlite3_open(cPath, &db)
        guard status == SQLITE_OK else {
            print("❌ 打开数据库失败: \(status)")
            db = nil
            return
        }

        // 禁用 mmap — 避免 purgeableCacheUnpin 死锁/活锁（Apple 平台特有 bug）
        applyPragma("mmap_size", value: "0")
        // 启用 WAL 模式 — 读写不互相阻塞
        applyPragma("journal_mode", value: "WAL")

        createTables()
        migrateIfNeeded()
        startRetentionTimer()
        print("✅ 数据库已就绪: \(dbPath)")
    }

    private func _openInMemory() {
        let status = sqlite3_open(":memory:", &db)
        guard status == SQLITE_OK else {
            print("❌ 打开内存数据库失败: \(status)")
            db = nil
            return
        }

        createTables()
        migrateIfNeeded()
        print("✅ 内存数据库已就绪")
    }

    // MARK: - Schema 迁移

    /// 基于 PRAGMA user_version 的增量迁移（幂等，每次启动自动执行）
    /// - Note: public 仅为 TestRunner 验证迁移逻辑；应用启动时已自动调用
    public func migrateIfNeeded() {
        guard let db else { return }

        var version: Int32 = 0
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        if sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &stmt, nil) == SQLITE_OK,
           sqlite3_step(stmt) == SQLITE_ROW {
            version = sqlite3_column_int(stmt, 0)
        }

        if version < 1 {
            // v1：cost 字段统一为 CNY（此前存的是 USD，展示时误当人民币）
            // 历史数据按默认汇率迁移；此后新写入在 ReasonixHookMonitor 中转换
            let rate = CurrencyConfig.defaultUsdToCnyRate
            let migrations = [
                "UPDATE hook_events SET cost = ROUND(cost * \(rate), 6) WHERE cost > 0;",
                "UPDATE hook_sessions SET total_cost = ROUND(total_cost * \(rate), 6) WHERE total_cost > 0;",
            ]
            for sql in migrations {
                if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
                    print("⚠️ 数据迁移 v1 失败: \(String(cString: sqlite3_errmsg(db)))")
                    return
                }
            }
            sqlite3_exec(db, "PRAGMA user_version = 1", nil, nil, nil)
            print("💱 数据迁移 v1 完成：cost 字段已统一为 CNY")
        }
    }

    /// 执行 PRAGMA 语句
    private func applyPragma(_ name: String, value: String) {
        guard let db else { return }
        let sql = "PRAGMA \(name)=\(value);"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
              sqlite3_step(stmt) == SQLITE_DONE else {
            print("⚠️ PRAGMA \(name) 设置失败: \(String(cString: sqlite3_errmsg(db)))")
            return
        }
    }

    /// 关闭数据库连接
    public func close() {
        serialQueue.sync {
            _close()
        }
    }

    private func _close() {
        retentionTimer?.cancel()
        retentionTimer = nil
        guard let db else { return }
        sqlite3_close(db)
        self.db = nil
    }

    /// 数据库是否可用
    public var isReady: Bool {
        serialQueue.sync { db != nil }
    }

    /// 执行查询，每行调用一次 handler
    public func query(sql: String, handler: @escaping (OpaquePointer) -> Void) {
        serialQueue.sync {
            _query(sql: sql, handler: handler)
        }
    }

    private func _query(sql: String, handler: (OpaquePointer) -> Void) {
        guard let db else { return }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return
        }

        while sqlite3_step(stmt) == SQLITE_ROW {
            handler(stmt!)
        }
    }

    // MARK: - 数据保留

    /// 明细数据保留天数（hook_events / hook_tool_calls）
    private static let eventRetentionDays = 90
    /// 会话汇总保留天数（hook_sessions，数据量小可保留更久）
    private static let sessionRetentionDays = 180
    /// 清理间隔（小时）
    private static let retentionIntervalHours = 24

    /// 启动每日清理定时器，并立即执行一次
    private func startRetentionTimer() {
        let timer = DispatchSource.makeTimerSource(queue: serialQueue)
        timer.schedule(deadline: .now() + 3600,
                       repeating: TimeInterval(Self.retentionIntervalHours * 3600),
                       leeway: .seconds(600))
        timer.setEventHandler { [weak self] in
            self?.purgeExpiredData()
        }
        timer.resume()
        retentionTimer = timer

        // 启动时立即执行一次（首次安装旧库可能已有大量历史数据）
        serialQueue.async { [weak self] in
            self?.purgeExpiredData()
        }
    }

    /// 删除超过保留期限的过期数据（幂等，可随时调用）
    /// - Note: public 仅为 TestRunner 验证清理逻辑；应用启动与每日定时自动执行
    public func purgeExpiredData() {
        guard let db else { return }
        let purgeSQL = [
            "DELETE FROM hook_events WHERE date(timestamp) < date('now', '-\(Self.eventRetentionDays) days');",
            "DELETE FROM hook_tool_calls WHERE date(started_at) < date('now', '-\(Self.eventRetentionDays) days');",
            "DELETE FROM hook_sessions WHERE date(updated_at) < date('now', '-\(Self.sessionRetentionDays) days');",
        ]
        var deleted = 0
        for sql in purgeSQL {
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
                  sqlite3_step(stmt) == SQLITE_DONE else {
                print("⚠️ 过期数据清理失败: \(String(cString: sqlite3_errmsg(db)))")
                continue
            }
            deleted += Int(sqlite3_changes(db))
        }
        if deleted > 0 {
            print("🧹 已清理 \(deleted) 条过期数据")
        }
    }

    // MARK: - 建表

    /// 创建所有需要的表（仅首次运行时执行）
    private func createTables() {
        // 创建 Reasonix Hook 事件表
        createHookTables()

        createIndexes()
    }

    /// 创建索引以优化查询性能
    private func createIndexes() {
        // Reasonix Hook 索引
        createHookIndexes()
    }

    // MARK: - Hook 表创建

    /// 创建 Reasonix Hook 事件相关表
    private func createHookTables() {
        let hookStatements = [
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
                source TEXT NOT NULL DEFAULT 'reasonix',  -- 数据来源：reasonix/claude/codex
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

        for sql in hookStatements {
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            let status = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
            guard status == SQLITE_OK else {
                print("❌ Hook 建表失败: \(String(cString: sqlite3_errmsg(db)))")
                return
            }

            if sqlite3_step(stmt) != SQLITE_DONE {
                print("❌ Hook 建表执行失败: \(String(cString: sqlite3_errmsg(db)))")
                return
            }
        }
    }

    /// 创建 Hook 相关索引
    private func createHookIndexes() {
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
                print("⚠️ 旧索引清理失败: \(String(cString: sqlite3_errmsg(db)))")
                continue
            }
        }

        // 表达式索引必须与查询中的 date(列, 偏移) 完全一致才能命中
        // 注意：SQLite 不允许在索引中使用非确定性函数（'localtime' 依赖系统时区），
        // 且 token 统计已改由官方 stats JSONL 驱动（按天文件，无需数据库按天查询），
        // 因此不再创建按天表达式索引，仅保留普通索引。
        let hookIndexes = [
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
            // token_usage 查询索引（统计按 date / date+hour / model 聚合）
            "CREATE INDEX IF NOT EXISTS idx_token_usage_date ON token_usage(date, is_turn);",
            "CREATE INDEX IF NOT EXISTS idx_token_usage_date_hour ON token_usage(date, hour, is_turn);",
            "CREATE INDEX IF NOT EXISTS idx_token_usage_model ON token_usage(date, model, is_turn);",
        ]

        for sql in hookIndexes {
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
                  sqlite3_step(stmt) == SQLITE_DONE else {
                print("⚠️ Hook 索引创建失败: \(String(cString: sqlite3_errmsg(db)))")
                continue
            }
        }
    }

    // MARK: - Token 用量记录（stats 导入）

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

    // MARK: - Hook 事件写入

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
                print("⚠️ hook_events 写入准备失败: \(String(cString: sqlite3_errmsg(db)))")
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
                print("⚠️ hook_events 写入失败: \(String(cString: sqlite3_errmsg(db)))")
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
                    print("⚠️ hook_sessions 更新失败: \(String(cString: sqlite3_errmsg(db)))")
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
                    print("⚠️ hook_sessions 插入准备失败: \(String(cString: sqlite3_errmsg(db)))")
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
                    print("⚠️ hook_sessions 插入失败: \(String(cString: sqlite3_errmsg(db)))")
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
                print("⚠️ hook_tool_calls 写入准备失败: \(String(cString: sqlite3_errmsg(db)))")
                return
            }

            sqlite3_bind_text(stmt, 1, (sessionId as NSString).utf8String, -1, nil)
            sqlite3_bind_int(stmt, 2, Int32(turn))
            sqlite3_bind_text(stmt, 3, (toolName as NSString).utf8String, -1, nil)
            self?.sqlite3_bind_text_or_null(stmt, 4, toolArgsJSON)
            sqlite3_bind_text(stmt, 5, (timestamp as NSString).utf8String, -1, nil)

            if sqlite3_step(stmt) != SQLITE_DONE {
                print("⚠️ hook_tool_calls 写入失败: \(String(cString: sqlite3_errmsg(db)))")
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
                print("⚠️ hook_tool_calls 更新准备失败: \(String(cString: sqlite3_errmsg(db)))")
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
                print("⚠️ hook_tool_calls 更新失败: \(String(cString: sqlite3_errmsg(db)))")
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

// MARK: - SQLite3 辅助扩展

private extension DatabaseManager {
    /// 绑定可空文本字段：nil 则绑定 NULL
    func sqlite3_bind_text_or_null(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(stmt, index, (value as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }
}
