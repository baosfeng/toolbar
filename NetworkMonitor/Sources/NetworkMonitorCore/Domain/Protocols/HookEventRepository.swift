import Foundation

// MARK: - Hook 事件仓储

/// Reasonix Hook 事件仓储协议 — 事件流水、会话汇总、工具调用的持久化与查询
///
/// 从 `DatabaseService` 中拆分（接口隔离原则）：调用方只需依赖本协议，
/// 不再被通用数据库访问接口和 Token 用量写入接口耦合。
public protocol HookEventRepository: AnyObject, Sendable {
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
