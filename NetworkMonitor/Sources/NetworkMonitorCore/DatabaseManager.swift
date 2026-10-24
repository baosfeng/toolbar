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
/// - 建表与历史表/索引结构：`DatabaseManager+LegacySchema.swift`（历史表为数据兼容保留）
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
