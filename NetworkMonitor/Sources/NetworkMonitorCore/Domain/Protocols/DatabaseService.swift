import Foundation
import SQLite3

// MARK: - 数据库服务

/// 数据库服务协议 — 统一数据库访问接口
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

    /// 写入一条系统采样数据
    func writeSystemSample(timestamp: TimeInterval, cpuUsage: Double,
                           memoryUsedMB: Int, memoryTotalMB: Int,
                           networkRx: UInt64, networkTx: UInt64)

    /// 写入击键批量数据
    func writeKeyPressBatch(count: Int, timestamp: TimeInterval)

    /// 写入一条事件
    func writeEvent(type: EventType, appName: String?, bundleID: String?,
                    windowTitle: String?, timestamp: TimeInterval)

    /// 立即刷新缓冲区，将事件写入数据库
    func flush()

    // MARK: - Reasonix Hook 操作

    /// 写入一条 Hook 事件流水
    func writeHookEvent(event: ReasonixHookEvent)

    /// 创建或更新会话汇总记录
    func upsertHookSession(event: ReasonixHookEvent)

    /// 创建工具调用记录
    func startHookToolCall(sessionId: String, turn: Int, toolName: String,
                          toolArgsJSON: String?, timestamp: String)

    /// 更新工具调用记录
    func finishHookToolCall(sessionId: String, turn: Int, toolName: String,
                           status: String, resultPreview: String?,
                           error: String?, timestamp: String)

    /// 查询活跃会话列表
    func queryActiveSessions(limit: Int) -> [[String: Any]]

    /// 查询指定会话的工具调用
    func queryToolCalls(sessionId: String, limit: Int) -> [[String: Any]]
}
