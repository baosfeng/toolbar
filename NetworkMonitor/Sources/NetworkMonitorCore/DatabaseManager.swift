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
    /// 只读连接指针（internal：只读连接生命周期的扩展文件要访问，见 DatabaseManager+ReadConnection.swift）
    var readDB: OpaquePointer?

    /// 删板事务的故障注入点：返回 true 即模拟「条目已删、板行删除失败」的崩溃现场
    ///
    /// 生产路径恒为 nil；TestRunner 用它守住 T1 的防复发断言（删一半必须整体回滚）。
    /// 放主类而不是板扩展：扩展不能有存储属性。
    public var deleteBoardFaultProbe: (() -> Bool)?

    /// readDB 的开合与取用互斥（查询持锁期间不会被 close 关掉连接）
    /// 只读连接的开合与取用互斥（internal：只读连接的扩展文件要访问，见 DatabaseManager+ReadConnection.swift）
    let readLock = NSLock()

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

        _migrateOnWriteQueue()
        // 只读连接必须在写连接建好表之后再开：READONLY 无法建表，也依赖 WAL / -shm 已就位
        openReadConnection()
        logger.info("数据库已就绪: \(LogRedaction.path(dbPath))")
    }

    private func _openInMemory() {
        let status = sqlite3_open(":memory:", &db)
        guard status == SQLITE_OK else {
            logger.error("打开内存数据库失败: \(status)")
            db = nil
            return
        }

        _migrateOnWriteQueue()
        // `:memory:` 是每连接私有的，第二个连接看不见它：只读查询自然退化为走写队列
        logger.info("内存数据库已就绪")
    }

    // MARK: - 连接参数与关闭

    /// 执行 PRAGMA 语句
    /// 设置 PRAGMA
    ///
    /// 用 `sqlite3_step` 判定成败时必须同时接受 `SQLITE_ROW`：
    /// `PRAGMA journal_mode = WAL` / `PRAGMA mmap_size = 0` 这类语句**会返回一行结果**，
    /// step 返回 `SQLITE_ROW` 而不是 `SQLITE_DONE`。只认 DONE 会把「设置成功」
    /// 记成失败（日志里那两条「another row available」就是这么来的），
    /// 让真正失败的 PRAGMA 淹没在假告警里。
    /// internal：只读连接打开时也要设同一份 mmap 口径（见 DatabaseManager+ReadConnection.swift）
    func applyPragma(_ name: String, value: String, on connection: OpaquePointer? = nil) {
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
        // 失败一律留痕：静默 return 会让「查不到数据」与「SQL 写错了」在调用方看起来一样
        guard let db else {
            logger.warning("数据库未就绪，查询被跳过: \(Self.sqlSummary(sql))")
            return
        }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.error("查询准备失败(\(Self.sqlSummary(sql))): \(String(cString: sqlite3_errmsg(db)))")
            return
        }

        var stepResult = sqlite3_step(stmt)
        while stepResult == SQLITE_ROW {
            handler(stmt!)
            stepResult = sqlite3_step(stmt)
        }
        // 正常收尾是 SQLITE_DONE；其余（约束 / 磁盘 / 忙）必须留痕，否则调用方只看到「没数据」
        if stepResult != SQLITE_DONE {
            logger.error("查询执行失败(\(Self.sqlSummary(sql))): step=\(stepResult) \(String(cString: sqlite3_errmsg(db)))")
        }
    }

    /// SQL 摘要：日志只留前 80 字符，避免整条语句刷屏
    static func sqlSummary(_ sql: String) -> String {
        let flattened = sql.replacingOccurrences(of: "\n", with: " ")
        return flattened.count <= 80 ? flattened : String(flattened.prefix(80)) + "…"
    }
}
