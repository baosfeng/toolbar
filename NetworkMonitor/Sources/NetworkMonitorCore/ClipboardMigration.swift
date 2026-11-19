import Foundation
import SQLite3

// MARK: - 剪贴板迁移（user_version 版本阶梯 → SchemaMigration）

/// 剪贴板表的注册式迁移
///
/// v1 / v2 段在 `DatabaseManager+ClipboardSchema.swift`，v3 起在 `ClipboardSchemaLadder.swift`；
/// 本文件只负责把它们**登记**进 `MigrationRegistry`，版本阶梯本身仍是原来那几段。
///
/// 幂等口径与旧版一致：每段自带 `PRAGMA user_version` 判断、建表一律 IF NOT EXISTS、
/// ALTER 前先探列，因此在已迁移过的库上重跑无副作用（迁移日志首次上线时会被真实重跑一次）。
///
/// - Note: 只持有 `owner` 作日志出口与版本阶梯实现的宿主，**迁移体只操作传入的连接**，
///   绝不读写 `owner` 自己的连接（否则在别的连接上跑登记表会串库）。
public struct ClipboardMigration: SchemaMigration {

    /// 迁移 id：写进 `schema_migration_log`
    public static let identifier = "clipboard.schema.ladder"
    /// 执行序：剪贴板表是基础表，排在 Harness 索引之前
    public static let order: Int32 = 1

    private let owner: DatabaseManager

    public init(owner: DatabaseManager) {
        self.owner = owner
    }

    public var identifier: String { Self.identifier }
    public var order: Int32 { Self.order }

    public func migrate(_ db: OpaquePointer) throws {
        owner.migrateClipboardSchema(db)
    }
}

// MARK: - Harness 索引迁移

/// Harness token 索引表的注册式迁移（建表幂等、无版本号，靠 CREATE IF NOT EXISTS）
public struct HarnessSchemaMigration: SchemaMigration {

    public static let identifier = "harness.schema.create"
    /// 执行序：排在剪贴板之后（写连接上先有剪贴板表，再建索引表）
    public static let order: Int32 = 2

    private let owner: DatabaseManager

    public init(owner: DatabaseManager) {
        self.owner = owner
    }

    public var identifier: String { Self.identifier }
    public var order: Int32 { Self.order }

    public func migrate(_ db: OpaquePointer) throws {
        guard owner.harnessMigrateSchema(db) else {
            throw DatabaseOperationError("Harness 索引建表失败")
        }
    }
}

// MARK: - 迁移入口（DatabaseManager 上的登记表接线）

/// 迁移的调度入口 —— 放在迁移机制自己的文件里（而非 `DatabaseManager` 族内）：
/// 「谁执行迁移」与「连接 / 建表 / 仓储」不同因变化，新增一张表只该动这里的注册表、不动仓储文件。
extension DatabaseManager {

    /// 迁移登记表：新增一张表 = 写一个 `SchemaMigration` + 在本方法里注册一行
    ///
    /// 登记表只登记、不执行；执行由 `migrateIfNeeded()` 在写连接上按 order 升序跑。
    public func makeMigrationRegistry() -> MigrationRegistry {
        let registry = MigrationRegistry(logger: logger)
        // ① 剪贴板表（user_version 版本阶梯 v1–v5）；② Harness 索引用表（建表幂等）
        registry.register(ClipboardMigration(owner: self))
        registry.register(HarnessSchemaMigration(owner: self))
        return registry
    }

    /// 按迁移登记表执行增量迁移（幂等，每次启动自动执行）
    /// - Note: public 仅为 TestRunner 验证迁移逻辑；应用启动时已自动调用
    public func migrateIfNeeded() {
        serialQueue.sync { _migrateOnWriteQueue() }
    }

    /// 忽略迁移日志强制重跑全部迁移（各迁移段自身幂等）
    ///
    /// 用途：版本号被外部改动 / 被旧版一次性写法写回低位时自愈；TestRunner 用它验证「低版本可重放升级」。
    public func replayMigrations() {
        serialQueue.sync {
            guard let db else { return }
            _ = makeMigrationRegistry().runAll(on: db, force: true)
        }
    }

    /// 迁移实际执行体：**必须在写队列上下文调用**（`_initialize` / `_openInMemory` 已在队列内，
    /// 再调 `migrateIfNeeded()` 会自己等自己，直接死锁）
    func _migrateOnWriteQueue() {
        guard let db else {
            logger.debug("数据库未就绪，跳过迁移")
            return
        }
        // 只读连接（READONLY）不能建表，因此迁移一律在写连接上跑完再开只读连接，
        // 否则首次索引前的聚合查询在只读连接上会报「no such table」
        _ = makeMigrationRegistry().runAll(on: db)
    }
}
