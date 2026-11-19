import Foundation
import SQLite3

// MARK: - 迁移登记表（新增一张表 = 写一个 migration + 注册一行）

/// 一次 schema 迁移的声明
///
/// 契约：
/// - `identifier` 稳定且唯一，写进 `schema_migration_log`（已执行过的不再重跑）；
/// - `order` 唯一，登记表**按 order 升序**执行，与注册顺序无关；
/// - `migrate` 自身必须幂等：老库（此机制上线前就已建好表的库）首次登记时
///   `schema_migration_log` 是空的，迁移会被真实重跑一遍。
public protocol SchemaMigration: Sendable {
    /// 稳定 id（如 `clipboard.schema.ladder`），写进迁移日志
    var identifier: String { get }
    /// 执行序：必须唯一、单调
    var order: Int32 { get }
    /// 在写连接上执行迁移（可调多条语句，由登记表包在一个事务里）
    func migrate(_ db: OpaquePointer) throws
}

/// 迁移登记表 —— 迁移的唯一入口
///
/// 取代 `migrateIfNeeded()` 里硬编码的函数调用序列：
/// 新增一张表 = 实现一个 `SchemaMigration` + `registry.register(...)` 一行，
/// 不需要改调度代码，也不需要改测试里的数字（`all.count` 由登记表自洽）。
public final class MigrationRegistry: @unchecked Sendable {

    /// 迁移日志表名（登记表自己建，属于机制的一部分）
    static let logTable = "schema_migration_log"

    private let logger: LoggingService
    private var migrations: [any SchemaMigration] = []

    /// - Parameter logger: 日志出口（缺省取全局）
    public init(logger: LoggingService = AppContext.shared.logger) {
        self.logger = logger
    }

    /// 按 order 升序的全部迁移（测试断言顺序用）
    public var all: [any SchemaMigration] {
        migrations.sorted { $0.order < $1.order }
    }

    /// 登记一条迁移；order 重复直接拒绝（唯一性是登记表的不变量，重复即编程错误）
    public func register(_ migration: any SchemaMigration) {
        if let clash = migrations.first(where: { $0.order == migration.order || $0.identifier == migration.identifier }) {
            logger.error("迁移登记拒绝：order \(migration.order) 或 id \(migration.identifier) 与 \(clash.identifier) 冲突")
            return
        }
        migrations.append(migration)
    }

    /// 执行所有未执行过的迁移（按 order 升序，每条一个事务，失败即停止）
    ///
    /// 失败姿态与旧版本阶梯一致：**不回退已成功迁移的版本号**，
    /// 记 `logger.error` 后停止，下次启动从失败那条重试。
    /// - Parameter force: true = 忽略迁移日志重跑全部（迁移段自身幂等；自愈与测试用）
    @discardableResult
    public func runAll(on db: OpaquePointer, force: Bool = false) -> Bool {
        guard createLogTableIfNeeded(db) else { return false }
        let applied = force ? [] : executedIdentifiers(db)
        for migration in all {
            guard !applied.contains(migration.identifier) else { continue }
            do {
                try NetworkMonitorCore.withTransaction(db, mode: .immediate) { conn in
                    try migration.migrate(conn)
                    try recordExecution(conn, identifier: migration.identifier)
                }
                logger.info("迁移完成：\(migration.identifier)（order \(migration.order)）")
            } catch {
                logger.error("迁移失败：\(migration.identifier)（order \(migration.order)）— \(error)")
                return false
            }
        }
        return true
    }

    /// 已执行过的迁移 id
    public func executedIdentifiers(_ db: OpaquePointer) -> Set<String> {
        _ = createLogTableIfNeeded(db)
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT identifier FROM \(Self.logTable);", -1, &stmt, nil) == SQLITE_OK else {
            logger.error("迁移日志查询准备失败：\(String(cString: sqlite3_errmsg(db)))")
            return []
        }
        var identifiers: Set<String> = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let text = sqlite3_column_text(stmt, 0) { identifiers.insert(String(cString: text)) }
        }
        return identifiers
    }

    // MARK: - 日志表

    private func createLogTableIfNeeded(_ db: OpaquePointer) -> Bool {
        let sql = """
        CREATE TABLE IF NOT EXISTS \(Self.logTable) (
          identifier  TEXT PRIMARY KEY,
          applied_at  REAL NOT NULL
        );
        """
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            logger.error("迁移日志表创建失败：\(String(cString: sqlite3_errmsg(db)))")
            return false
        }
        return true
    }

    private func recordExecution(_ db: OpaquePointer, identifier: String) throws {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO \(Self.logTable) (identifier, applied_at) VALUES (?, ?);",
                                 -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseOperationError("迁移日志写入准备失败：\(String(cString: sqlite3_errmsg(db)))")
        }
        sqlite3_bind_text(stmt, 1, identifier, -1, DatabaseManager.sqliteTransient)
        sqlite3_bind_double(stmt, 2, Date().timeIntervalSince1970)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseOperationError("迁移日志写入失败：\(String(cString: sqlite3_errmsg(db)))")
        }
    }
}
