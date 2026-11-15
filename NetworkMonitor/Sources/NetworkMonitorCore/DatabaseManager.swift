import Foundation
import SQLite3

/// 数据库管理器：管理 SQLite 数据库的初始化和基本操作
/// 数据存储在 ~/Library/Application Support/macMonitor/monitor.db
///
/// 线程模型（读写分队列，两条连接）：
/// - 写入 / 索引 / 建表：`serialQueue` + 写连接 `db`
/// - 只读查询：`readQueue` + 独立只读连接 `readDB`（`SQLITE_OPEN_READONLY`）
/// - 两条队列互不阻塞：WAL 下只读连接**立即**读到写连接已提交的内容，不依赖 checkpoint 时机
/// - 只读连接不可用时（内存库 / `-shm` 不可写）只读查询退化为走写队列，语义与分队列前一致
/// - `PRAGMA mmap_size=0` 禁用 mmap，避免 Apple 平台 mmap/purgeable 缓存导致的死锁（两条连接口径一致）
///
/// 为什么分队列：面板打开时主线程的剪贴板读取与后台索引收尾的全表聚合同挤一条队列，
/// 单次聚合 0.2–1.0 s，主线程排队拿不到队列 → 系统判「未响应」（2026-11 事故）。
///
/// 测试支持：
/// - `initializeInMemory()` 使用 `:memory:` 数据库（内存库无法共享给第二个连接，只读走写队列）
/// - `init(path:)` 指定文件路径（只读连接可见性测试用）
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

    /// 写队列 — 写入 / 索引 / 建表在此队列上执行（internal：供同模块仓储扩展访问）
    /// 队列自带排队等待计时（> 200 ms 记一条，见 DatabaseQueue）
    let serialQueue = DatabaseQueue(label: "com.bsfeng.yilan.database")

    /// 只读队列 — 只读查询在此队列上执行，与写队列并行（internal：供同模块仓储扩展访问）
    let readQueue = DatabaseQueue(label: "com.bsfeng.yilan.database.read")

    /// 只读连接指针（只在 readQueue 上使用；nil = 不可用，只读查询退化为写队列）
    private var readDB: OpaquePointer?

    /// readDB 的开合与取用互斥（查询持锁期间不会被 close 关掉连接）
    private let readLock = NSLock()

    /// 显式指定的数据库文件路径（nil = 默认路径）
    private let pathOverride: String?

    /// 数据库文件路径
    public private(set) lazy var dbPath: String = {
        let path = pathOverride ?? Self.defaultDatabasePath()
        try? FileManager.default.createDirectory(
            at: URL(fileURLWithPath: path).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        return path
    }()

    /// 只读连接是否可用（false = 只读查询当前走写队列；供测试与日志判别）
    public var isUsingDedicatedReadConnection: Bool {
        readLock.lock()
        defer { readLock.unlock() }
        return readDB != nil
    }

    /// 默认数据库路径：~/Library/Application Support/macMonitor/monitor.db
    private static func defaultDatabasePath() -> String {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport.appendingPathComponent("macMonitor", isDirectory: true)
            .appendingPathComponent("monitor.db").path
    }

    /// - Parameter path: 自定义数据库文件路径（nil = 默认路径）
    public init(path: String? = nil) {
        pathOverride = path
    }

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
        // 路径必须用 withCString 保证在整个 sqlite3_open 调用期间有效：
        // `(dbPath as NSString).utf8String` 的临时桥接对象在表达式结束即可释放，
        // 得到的是悬空指针，sqlite3_open 可能拿到空串 → 静默建出一个空库。
        let status = dbPath.withCString { sqlite3_open($0, &db) }
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
        // 只读连接必须在写连接建好表之后再开：READONLY 无法建表，也依赖 WAL / -shm 已就位
        openReadConnection()
        logger.info("数据库已就绪: \(LogRedaction.path(dbPath))")
    }

    /// 打开只读连接（与写连接指向同一份 WAL，各自独立持有）
    ///
    /// 用 `SQLITE_OPEN_READONLY`：连接级只读，写语句会直接被 SQLite 拒掉（测试有断言）。
    /// WAL 模式下只读连接读的是最新已提交快照，写连接 checkpoint 与否都不影响可见性。
    private func openReadConnection() {
        var conn: OpaquePointer?
        let status = dbPath.withCString {
            sqlite3_open_v2($0, &conn, SQLITE_OPEN_READONLY, nil)
        }
        guard status == SQLITE_OK, let conn else {
            if let conn { sqlite3_close(conn) }
            logger.warning("只读连接打开失败（\(status)），只读查询退回写队列")
            return
        }
        // mmap 与写连接同口径：purgeable 缓存死锁的规避点不能只做一半
        applyPragma("mmap_size", value: "0", on: conn)
        readLock.lock()
        readDB = conn
        readLock.unlock()
    }

    private func _openInMemory() {
        let status = sqlite3_open(":memory:", &db)
        guard status == SQLITE_OK else {
            logger.error("打开内存数据库失败: \(status)")
            db = nil
            return
        }

        migrateIfNeeded()
        // `:memory:` 是每连接私有的，第二个连接看不见它：只读查询自然退化为走写队列
        logger.info("内存数据库已就绪")
    }

    // MARK: - Schema 迁移

    /// 基于 PRAGMA user_version 的增量迁移（幂等，每次启动自动执行）
    /// - Note: public 仅为 TestRunner 验证迁移逻辑；应用启动时已自动调用
    public func migrateIfNeeded() {
        // 剪贴板历史表（幂等建表，user_version 迁移到 2）
        migrateClipboardSchema()
        // Harness 索引表：只读连接（READONLY）不能建表，必须在写连接上先建好，
        // 否则首次索引前的聚合查询在只读连接上会报「no such table」
        if let db { _ = harnessMigrateSchema(db) }
    }

    /// 执行 PRAGMA 语句
    /// 设置 PRAGMA
    ///
    /// 用 `sqlite3_step` 判定成败时必须同时接受 `SQLITE_ROW`：
    /// `PRAGMA journal_mode = WAL` / `PRAGMA mmap_size = 0` 这类语句**会返回一行结果**，
    /// step 返回 `SQLITE_ROW` 而不是 `SQLITE_DONE`。只认 DONE 会把「设置成功」
    /// 记成失败（日志里那两条「another row available」就是这么来的），
    /// 让真正失败的 PRAGMA 淹没在假告警里。
    private func applyPragma(_ name: String, value: String, on connection: OpaquePointer? = nil) {
        guard let db = connection ?? db else { return }
        let sql = "PRAGMA \(name)=\(value);"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.warning("PRAGMA \(name) 准备失败: \(String(cString: sqlite3_errmsg(db)))")
            return
        }
        let stepResult = sqlite3_step(stmt)
        guard stepResult == SQLITE_DONE || stepResult == SQLITE_ROW else {
            logger.warning("PRAGMA \(name) 设置失败: \(String(cString: sqlite3_errmsg(db)))")
            return
        }
    }

    /// 关闭数据库连接
    public func close() {
        // 只读连接先关：等只读队列上在途查询跑完，再在锁内关连接（不会在别人手里拔掉连接）
        readQueue.sync { }
        readLock.lock()
        if let readDB { sqlite3_close(readDB) }
        readDB = nil
        readLock.unlock()
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

    // MARK: - 只读访问

    /// 只读执行：有只读连接时走只读队列，否则退化为写队列（内存库 / 连接未开）
    ///
    /// 读连接与写连接各自独立持有 → 后台索引写库期间，只读查询不再排在写队列后面。
    /// - Parameters:
    ///   - fallback: 数据库不可用时的返回值
    ///   - body: 在对应队列上执行；**内部不得再调本类的队列同步接口**，否则死锁
    @inline(__always)
    func withReadDB<T>(_ fallback: T, _ body: (OpaquePointer) -> T) -> T {
        readLock.lock()
        guard let conn = readDB else {
            readLock.unlock()
            return serialQueue.sync { () -> T in
                guard let db else { return fallback }
                return body(db)
            }
        }
        // 持锁到查询结束：close() 不会在查询中间关掉这条连接
        defer { readLock.unlock() }
        return readQueue.sync { body(conn) }
    }
}

// MARK: - SQLite3 辅助扩展

extension DatabaseManager {
    /// SQLITE_TRANSIENT — 让 SQLite 在绑定时就复制文本
    ///
    /// 传 nil（= SQLITE_STATIC）时 SQLite 只保存指针、不复制内容，而
    /// `(value as NSString).utf8String` 返回的缓冲区随桥接对象释放即失效
    /// （表达式结束、下一行准备语句、下一次分配都可能复用它），
    /// 于是写进库的可能是上一次的字符串或乱码。所有绑定一律走 TRANSIENT。
    ///
    /// 用局部量而非全局常量：非 Sendable 的 C 函数指针做全局常量会触发 Swift 6 并发检查。
    static var sqliteTransient: sqlite3_destructor_type {
        unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    }

    /// 绑定文本字段（自动复制）
    func sqlite3_bind_text_copy(_ stmt: OpaquePointer?, _ index: Int32, _ value: String) {
        sqlite3_bind_text(stmt, index, value, -1, Self.sqliteTransient)
    }

    /// 绑定可空文本字段：nil 则绑定 NULL
    func sqlite3_bind_text_or_null(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text_copy(stmt, index, value)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }
}
