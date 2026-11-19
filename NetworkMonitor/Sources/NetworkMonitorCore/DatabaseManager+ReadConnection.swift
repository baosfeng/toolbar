import Foundation
import SQLite3

// MARK: - 只读连接的生命周期

/// 只读连接的开 / 关 / 取用 —— 从 `DatabaseManager.swift` 拆出：
/// 双连接（写连接 + READONLY 只读连接）是一条独立的生命周期职责，与建表 / 查询语句无关。
/// 放宽为 internal 的成员：`db` / `readDB` / `readLock` / `readQueue` / `logger` / `dbPath` / `serialQueue`。
extension DatabaseManager {

    /// 打开只读连接（与写连接指向同一份 WAL，各自独立持有）
    ///
    /// 由 `_initialize()` 在迁移跑完后调用：READONLY 无法建表，也不该在建表前就持有旧快照。
    ///
    /// 用 `SQLITE_OPEN_READONLY`：连接级只读，写语句会直接被 SQLite 拒掉（测试有断言）。
    /// WAL 模式下只读连接读的是最新已提交快照，写连接 checkpoint 与否都不影响可见性。
    /// internal：由 `_initialize()` 在迁移跑完后调用（见 DatabaseManager.swift）
    func openReadConnection() {
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
