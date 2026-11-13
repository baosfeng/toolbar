import Foundation

// MARK: - 删除二次确认状态机

/// 删除类操作的二次确认状态机 — 纯逻辑，App 层只负责提示文案与调用时机
///
/// 语义（设计规格 2.3-2）：
/// 1. 首次请求：登记待确认标识与时刻，返回 `true`（需确认）；
/// 2. 同一标识在窗口内再次请求：清理登记并返回 `false`（可执行）；
/// 3. 换了标识：打断上一次确认，重新进入确认态并返回 `true`；
/// 4. 超过窗口（默认 2.0s）或时刻回拨：旧登记失效，重新进入确认态并返回 `true`。
/// 单条删除与「清空历史」各持一个实例，状态互不串味。
public struct ClipboardDeleteConfirm: Sendable, Equatable {

    /// 默认确认窗口（秒）
    public static let defaultWindow: TimeInterval = 2.0

    /// 确认窗口（秒）
    public let window: TimeInterval
    /// 待确认的操作标识（单条删除传条目 ID，清空历史传调用方固定键）
    public private(set) var pendingID: UUID?
    /// 待确认的登记时刻（秒）
    public private(set) var pendingAt: TimeInterval?

    public init(window: TimeInterval = ClipboardDeleteConfirm.defaultWindow) {
        self.window = window
    }

    /// 是否存在待确认登记
    public var hasPending: Bool { pendingID != nil && pendingAt != nil }

    /// 请求执行一次删除类操作
    /// - Parameters:
    ///   - id: 操作标识（单条删除用条目 ID；清空历史用固定键）
    ///   - now: 当前时刻（秒）
    /// - Returns: `true` = 需确认（首次 / 换了对象 / 已超窗）；`false` = 可执行（窗口内二次请求，登记已清理）
    public mutating func requestDelete(id: UUID, now: TimeInterval) -> Bool {
        if pendingID == id, let pendingAt, now >= pendingAt, now - pendingAt <= window {
            reset()
            return false
        }
        pendingID = id
        pendingAt = now
        return true
    }

    /// 读取待确认登记在指定时刻是否仍有效（面板据此判断确认提示是否还有意义）
    public func isPending(at now: TimeInterval) -> Bool {
        guard pendingID != nil, let pendingAt else { return false }
        return now >= pendingAt && now - pendingAt <= window
    }

    /// 显式清理待确认登记（执行完操作或面板收起时调用）
    public mutating func reset() {
        pendingID = nil
        pendingAt = nil
    }
}
