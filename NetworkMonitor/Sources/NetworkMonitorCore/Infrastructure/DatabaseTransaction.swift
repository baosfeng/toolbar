import Foundation
import SQLite3

// MARK: - 事务原语（全仓唯一出口）

/// 事务模式：`deferred` = 首条语句才取写锁（等价旧 `BEGIN`）；
/// `immediate` = 开事务即取写锁（等价旧 `BEGIN IMMEDIATE`，写入意图明确时避免中途升级失败）。
public enum DatabaseTransactionMode: Sendable {
    case deferred
    case immediate

    /// 开启事务的 SQL（`BEGIN` 字面量只出现在本文件）
    var beginSQL: String {
        switch self {
        case .deferred: return "BEGIN"
        case .immediate: return "BEGIN IMMEDIATE"
        }
    }
}

/// 事务自身失败（开启 / 提交 / 回滚 / 连接不可用）；业务失败用 `DatabaseOperationError`
public struct DatabaseTransactionError: Error, CustomStringConvertible, Sendable {
    public enum Stage: String, Sendable {
        case begin = "开启事务"
        case commit = "提交事务"
        case connection = "连接不可用"
    }

    public let stage: Stage
    public let detail: String

    public init(stage: Stage, detail: String) {
        self.stage = stage
        self.detail = detail
    }

    public var description: String { "\(stage.rawValue)失败：\(detail)" }
}

/// 事务体内的业务失败：抛出即由所属事务整体回滚，`reason` 进调用方的日志标签
public struct DatabaseOperationError: Error, Equatable, CustomStringConvertible, Sendable {
    public let reason: String

    public init(_ reason: String) {
        self.reason = reason
    }

    public var description: String { reason }
}

/// 事务深度登记：同一条连接上嵌套调用 `withTransaction` 时不再开第二个事务
///
/// 为什么按连接指针记而不是按线程记：`DatabaseQueue.sync` 在调用方线程上执行，
/// 嵌套调用与外层同线程可依赖，但真正的判据是「同一条连接上是否已有事务」
/// （两条连接各自可以各有一个事务，混按线程记会误判）。
private final class TransactionScopeRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var depths: [OpaquePointer: Int] = [:]

    /// 进入事务作用域：返回 true = 本次需要开新事务；false = 已在外层事务内（嵌套执行）
    func enter(_ db: OpaquePointer) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let depth = depths[db, default: 0]
        depths[db] = depth + 1
        return depth == 0
    }

    /// 离开事务作用域（最外层离开时清掉登记，避免指针复用误判）
    func leave(_ db: OpaquePointer) {
        lock.lock()
        defer { lock.unlock() }
        guard let depth = depths[db] else { return }
        if depth <= 1 {
            depths[db] = nil
        } else {
            depths[db] = depth - 1
        }
    }
}

private let transactionScopes = TransactionScopeRegistry()

// MARK: - 原语

/// 在给定连接上执行一个事务：`body` 正常返回即提交，抛出即整体回滚并原样抛出
///
/// **一个业务动作 = 一个事务**：调用方把「一组必须同生共死的写入」放进同一个 `body`，
/// 不要再手写 BEGIN / COMMIT / ROLLBACK —— 事务字面量只允许出现在本文件
/// （`grep -rn 'BEGIN\|COMMIT\|ROLLBACK' Sources --include='*.swift'` 除本文件外应零命中）。
///
/// 嵌套语义：已在同一连接的事务内时，本函数**不开新事务**，直接执行 `body`，
/// 由最外层决定提交 / 回滚（内层抛出会被夹在外层事务里一起回滚）。
///
/// - Important: 直接操作连接指针、不调度队列，只能在写队列上下文（`serialQueue`）内调用；
///   `body` 内不得调用任何会再次调度队列的仓储方法，否则死锁。
public func withTransaction<T>(_ db: OpaquePointer,
                               mode: DatabaseTransactionMode = .deferred,
                               _ body: (OpaquePointer) throws -> T) throws -> T {
    guard transactionScopes.enter(db) else {
        // 嵌套：外层已有事务，本次只执行内容，不 BEGIN / 不 COMMIT
        defer { transactionScopes.leave(db) }
        return try body(db)
    }
    defer { transactionScopes.leave(db) }

    guard transactionExec(db, mode.beginSQL) else {
        throw DatabaseTransactionError(stage: .begin, detail: transactionErrorMessage(db))
    }
    do {
        let value = try body(db)
        guard transactionExec(db, "COMMIT") else {
            let detail = transactionErrorMessage(db)
            _ = transactionExec(db, "ROLLBACK")
            throw DatabaseTransactionError(stage: .commit, detail: detail)
        }
        return value
    } catch {
        // 业务失败（或提交失败已在上面处理）统一回滚；回滚本身失败只是把现场交回上层日志
        _ = transactionExec(db, "ROLLBACK")
        throw error
    }
}

// MARK: - 队列入口

extension DatabaseManager {

    /// 在写队列上执行一个事务 —— 业务层唯一入口（仓储方法内部用 `withTransaction(db:)`）
    ///
    /// - Note: 与既有仓储方法同一线程模型：调用方不能在已持有写队列时再调本方法（死锁）。
    public func withTransaction<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        let outcome: Result<T, Error> = serialQueue.sync { () -> Result<T, Error> in
            guard let db else {
                return .failure(DatabaseTransactionError(stage: .connection, detail: "数据库未就绪"))
            }
            return Result { try NetworkMonitorCore.withTransaction(db, mode: .deferred, body) }
        }
        return try outcome.get()
    }
}

// MARK: - 共用辅助

/// 执行无返回值的 SQL（事务原语内部用，语义与 `clipExec` 一致）
private func transactionExec(_ db: OpaquePointer, _ sql: String) -> Bool {
    sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
}

private func transactionErrorMessage(_ db: OpaquePointer) -> String {
    String(cString: sqlite3_errmsg(db))
}
