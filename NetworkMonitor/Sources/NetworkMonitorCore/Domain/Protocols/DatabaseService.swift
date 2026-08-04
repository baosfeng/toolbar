import Foundation
import SQLite3

// MARK: - 数据库服务

/// 数据库服务协议 — 统一数据库访问接口
///
/// 只保留通用连接管理与查询能力；领域写操作见
/// `HookEventRepository`（Hook 事件）与 `TokenUsageRepository`（Token 用量）。
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
}

// MARK: - 完整数据库能力组合

/// 应用所需完整数据库能力 — 通用访问 + Hook 仓储 + Token 仓储
///
/// 组合根与 UI 层传递数据库实例时使用此组合类型，避免依赖具体实现类。
public typealias AppDatabase = DatabaseService & HookEventRepository & TokenUsageRepository
