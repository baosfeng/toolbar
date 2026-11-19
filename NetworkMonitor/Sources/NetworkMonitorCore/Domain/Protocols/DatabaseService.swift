import Foundation
import SQLite3

// MARK: - 数据库服务

/// 数据库服务协议 — 统一数据库访问接口
///
/// 只保留通用连接管理与查询能力；领域写操作见 `ClipboardRepository`（剪贴板历史）。
///
/// 所有写操作必须线程安全；查询通过 `query(sql:handler:)` 在串行队列上执行。
public protocol DatabaseService: AnyObject, Sendable {
    /// 数据库是否已就绪
    var isReady: Bool { get }

    /// 初始化数据库（基于默认文件路径）
    func initialize()

    /// 初始化内存数据库（仅测试用）
    func initializeInMemory()

    /// 关闭数据库连接
    func close()

    /// 执行查询，每行回调一次 handler
    func query(sql: String, handler: @escaping (OpaquePointer) -> Void)

    /// 在一个事务里执行一组写入：正常返回即提交，抛出即整体回滚（一个业务动作 = 一个事务）
    ///
    /// 实现必须把 `body` 调度到写队列上执行，且嵌套调用不再开第二个事务
    /// （见 `DatabaseTransaction.swift`）。调用方不得在已持有写队列时再调本方法。
    func withTransaction<T>(_ body: (OpaquePointer) throws -> T) throws -> T
}

// MARK: - 完整数据库能力组合

/// 应用所需完整数据库能力 — 通用访问 + 剪贴板仓储 + OCR 结果回写
///
/// 组合根与 UI 层传递数据库实例时使用此组合类型，避免依赖具体实现类。
/// OCR 单列成独立协议（识别是后台异步写、生命周期与采集不同），这里只做能力合并。
public typealias AppDatabase = DatabaseService & ClipboardRepository & ClipboardOCRRepository
