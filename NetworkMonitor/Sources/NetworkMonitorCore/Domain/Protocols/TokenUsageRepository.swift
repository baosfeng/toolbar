import Foundation

// MARK: - Token 用量仓储

/// Token 用量记录仓储协议 — stats JSONL 导入数据的持久化
///
/// 从 `DatabaseService` 中拆分（接口隔离原则）：导入器只需依赖本协议，
/// 不关心通用数据库访问与 Hook 领域操作。
public protocol TokenUsageRepository: AnyObject, Sendable {
    /// 插入一条 token 用量记录（幂等：重复导入自动忽略）
    func insertTokenUsage(source: String, date: String, hour: Int, record: ReasonixStatsRecord)
}
