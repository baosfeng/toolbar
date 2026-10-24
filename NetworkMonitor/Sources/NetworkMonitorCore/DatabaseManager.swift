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
public final class DatabaseManager: @unchecked Sendable, DatabaseService {

    // MARK: - 属性

    /// SQLite 连接指针（internal：供同模块仓储扩展访问）
    var db: OpaquePointer?

    /// 日志服务
    public var logger: LoggingService = AppContext.shared.logger

    /// 串行队列 — 所有数据库操作在此队列上执行（internal：供同模块仓储扩展访问）
    let serialQueue = DispatchQueue(label: "com.example.NetworkMonitor.database")

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

        migrateIfNeeded()
        logger.info("数据库已就绪: \(dbPath)")
    }

    private func _openInMemory() {
        let status = sqlite3_open(":memory:", &db)
        guard status == SQLITE_OK else {
            logger.error("打开内存数据库失败: \(status)")
            db = nil
            return
        }

        migrateIfNeeded()
        logger.info("内存数据库已就绪")
    }

    // MARK: - Schema 迁移

    /// 基于 PRAGMA user_version 的增量迁移（幂等，每次启动自动执行）
    /// - Note: public 仅为 TestRunner 验证迁移逻辑；应用启动时已自动调用
    public func migrateIfNeeded() {
        // 剪贴板历史表（幂等建表，user_version 迁移到 2）
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
