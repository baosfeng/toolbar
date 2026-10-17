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
///
/// 协议实现分布：
/// - `DatabaseService`（连接与查询）：本文件
/// - `ClipboardRepository`（剪贴板历史）：`DatabaseManager+ClipboardRepository.swift`（建表与迁移见 `+ClipboardSchema.swift`）
///
/// 历史表说明：`hook_events` / `hook_sessions` / `hook_tool_calls` / `token_usage` 四张表
/// 为历史数据保留（旧版本 AI 助手事件与 token 统计落库），代码已不再使用，
/// 也不做删表迁移，避免误删用户既有数据。
public final class DatabaseManager: @unchecked Sendable, DatabaseService {

    // MARK: - 属性

    /// SQLite 连接指针（internal：供同模块仓储扩展访问）
    var db: OpaquePointer?

    /// 日志服务
    public var logger: LoggingService = AppContext.shared.logger

    /// 串行队列 — 所有数据库操作在此队列上执行（internal：供同模块仓储扩展访问）
    let serialQueue = DispatchQueue(label: "com.example.NetworkMonitor.database")

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
            logger.error("数据库路径无效")
            return
        }

        let status = sqlite3_open(cPath, &db)
        guard status == SQLITE_OK else {
            logger.error("打开数据库失败: \(status)")
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
        logger.info("数据库已就绪: \(dbPath)")
    }

    private func _openInMemory() {
        let status = sqlite3_open(":memory:", &db)
        guard status == SQLITE_OK else {
            logger.error("打开内存数据库失败: \(status)")
            db = nil
            return
        }

        createTables()
        migrateIfNeeded()
        logger.info("内存数据库已就绪")
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
            // 仅处理历史数据（相关写入链路已移除）：表为历史数据保留，代码已不再使用
            let rate = CurrencyConfig.defaultUsdToCnyRate
            let migrations = [
                "UPDATE hook_events SET cost = ROUND(cost * \(rate), 6) WHERE cost > 0;",
                "UPDATE hook_sessions SET total_cost = ROUND(total_cost * \(rate), 6) WHERE total_cost > 0;",
            ]
            for sql in migrations {
                if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
                    logger.warning("数据迁移 v1 失败: \(String(cString: sqlite3_errmsg(db)))")
                    return
                }
            }
            sqlite3_exec(db, "PRAGMA user_version = 1", nil, nil, nil)
            logger.info("数据迁移 v1 完成：cost 字段已统一为 CNY")
        }

        // v2：剪贴板历史表（幂等建表，user_version 1 → 2）
        migrateClipboardSchema()
    }

    /// 执行 PRAGMA 语句
    private func applyPragma(_ name: String, value: String) {
        guard let db else { return }
        let sql = "PRAGMA \(name)=\(value);"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
              sqlite3_step(stmt) == SQLITE_DONE else {
            logger.warning("PRAGMA \(name) 设置失败: \(String(cString: sqlite3_errmsg(db)))")
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

    /// 明细数据保留天数（hook_events / hook_tool_calls，历史表，代码已不再写入）
    private static let eventRetentionDays = 90
    /// 会话汇总保留天数（hook_sessions，历史表，数据量小可保留更久）
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
                logger.warning("过期数据清理失败: \(String(cString: sqlite3_errmsg(db)))")
                continue
            }
            deleted += Int(sqlite3_changes(db))
        }
        if deleted > 0 {
            logger.info("已清理 \(deleted) 条过期数据")
        }
    }

    // MARK: - 建表

    /// 创建所有需要的表（仅首次运行时执行）
    private func createTables() {
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

// MARK: - SQLite3 辅助扩展

extension DatabaseManager {
    /// 绑定可空文本字段：nil 则绑定 NULL
    func sqlite3_bind_text_or_null(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(stmt, index, (value as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }
}
