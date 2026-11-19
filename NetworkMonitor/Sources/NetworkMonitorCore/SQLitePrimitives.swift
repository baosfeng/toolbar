import Foundation
import SQLite3

// MARK: - SQLite 原语辅助（exec / user_version / 绑定）

/// 与 `DatabaseManager` 的领域职责无关的 sqlite3 原语：执行无结果 SQL、读 `user_version`、
/// 绑定文本（一律 SQLITE_TRANSIENT）。收敛在一处，仓储扩展与迁移段共用同一份口径。
extension DatabaseManager {

    /// 执行无返回值的 SQL，成功返回 true
    func clipExec(_ db: OpaquePointer, _ sql: String) -> Bool {
        sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    }

    /// 读取 PRAGMA user_version
    func clipUserVersion(_ db: OpaquePointer) -> Int32 {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &stmt, nil) == SQLITE_OK,
              sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return sqlite3_column_int(stmt, 0)
    }

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
