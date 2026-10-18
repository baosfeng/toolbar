import Foundation

// MARK: - 会话状态机

/// 会话状态机 — 所有状态迁移集中在此处，便于单测穷举非法迁移
///
/// 主链路（设计文档 §4）：
/// `pending → offering → awaitingConfirm → transferring → verifying → completed`
/// 任一活动状态均可转 `failed` / `cancelled`；已配对设备可跳过等待确认：
/// `offering → transferring`。
public enum TransferSessionMachine {

    /// 从某状态允许迁入的目标状态集合
    public static func allowedTargets(from state: TransferState) -> Set<TransferState> {
        switch state {
        case .pending:
            return [.offering, .failed, .cancelled]
        case .offering:
            return [.awaitingConfirm, .transferring, .failed, .cancelled]
        case .awaitingConfirm:
            return [.transferring, .failed, .cancelled]
        case .transferring:
            return [.verifying, .failed, .cancelled]
        case .verifying:
            return [.completed, .failed, .cancelled]
        case .completed, .failed, .cancelled:
            return []
        }
    }

    /// 是否允许迁移
    public static func canTransition(from: TransferState, to: TransferState) -> Bool {
        allowedTargets(from: from).contains(to)
    }

    /// 执行迁移 — 非法迁移抛 `illegalTransition`（不静默纠正）
    @discardableResult
    public static func transition(_ from: TransferState, to: TransferState) throws -> TransferState {
        guard canTransition(from: from, to: to) else {
            throw TransferError.illegalTransition(from: from, to: to)
        }
        return to
    }

    /// 全部状态对（供测试穷举）
    public static var allTransitions: [(from: TransferState, to: TransferState)] {
        TransferState.allCases.flatMap { from in
            TransferState.allCases.map { to in (from, to) }
        }
    }
}

// MARK: - 会话推进

/// 会话推进器 — 持有会话并保证状态迁移合法
///
/// 业务侧只调用 `advance(to:)` / `updateFileProgress(fileId:transferred:)`，
/// 不直接改 `session.state`，避免绕过状态机。
public struct TransferSessionRunner {

    /// 当前会话
    public private(set) var session: TransferSession

    public init(session: TransferSession) {
        self.session = session
    }

    /// 迁移到目标状态
    public mutating func advance(to state: TransferState) throws {
        let next = try TransferSessionMachine.transition(session.state, to: state)
        session.state = next
    }

    /// 更新单个文件进度（越界值按 0…size 收敛）
    public mutating func updateFileProgress(fileId: String, transferred: Int64) {
        guard let index = session.index(ofFile: fileId) else { return }
        let size = session.files[index].size
        session.files[index].transferred = min(max(0, transferred), max(0, size))
    }

    /// 全部文件是否已传完
    public var allFilesCompleted: Bool {
        session.files.allSatisfy { $0.transferred >= $0.size }
    }
}
