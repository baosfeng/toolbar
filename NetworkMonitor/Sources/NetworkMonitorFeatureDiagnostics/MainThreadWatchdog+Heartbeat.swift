import Foundation
import NetworkMonitorCore

// MARK: - 心跳现场

/// 心跳现场 — 最后一次心跳时刻 + 停顿时的上下文（分页 / 展开态 / 索引状态）
///
/// 从看门狗里拆成**值类型**的理由：
/// - 看护线程只读「最后一次心跳时存下的上下文」，不回头问主线程（真卡住时会一起卡住）；
///   把这份现场独立出来，锁内只剩读改写，日志在锁外拼；
/// - 停顿判定与「同一次停顿只记一条」的口径是纯逻辑，TestRunner 能跨 target 直接断言，
///   不必起定时器、不必阻塞主线程去等一条真停顿。
public struct MainThreadHeartbeat: Equatable, Sendable {

    /// 一次停顿的现场（判定成立时由 `takeStall(at:)` 返回）
    public struct Stall: Equatable, Sendable {
        /// 距上次心跳的间隔（秒）
        public let gapSeconds: Double
        /// 最后一次心跳携带的分页
        public let tab: String
        /// 最后一次心跳时面板是否展开
        public let panelShown: Bool
        /// 最后一次心跳时的索引状态
        public let indexingState: String
    }

    /// 最后一次心跳的单调时钟（纳秒，改系统时间不影响判定）
    public private(set) var lastBeatNanoseconds: UInt64
    /// 最后一次心跳携带的分页
    public private(set) var tab = "-"
    /// 最后一次心跳时面板是否展开
    public private(set) var panelShown = false
    /// 最后一次心跳时的索引状态
    public private(set) var indexingState = "-"
    /// 本次停顿是否已记过（同一次停顿只记一条，心跳恢复时清位）
    public private(set) var reportedStall = false

    /// 以当前时刻为起点构造（看门狗在 init 时取 `DispatchTime.now()`）
    public init(now: UInt64) {
        lastBeatNanoseconds = now
    }

    /// 只打点（心跳块 / sendEvent 等高频路径，不带上下文）
    public mutating func beat(at now: UInt64) {
        lastBeatNanoseconds = now
        reportedStall = false
    }

    /// 打点 + 更新「停顿现场」上下文（tick 路径，每个刷新节拍一次）
    public mutating func beat(at now: UInt64, tab: String, panelShown: Bool, indexingState: String) {
        lastBeatNanoseconds = now
        self.tab = tab
        self.panelShown = panelShown
        self.indexingState = indexingState
        reportedStall = false
    }

    /// 停顿判定：超过阈值且本次停顿还没报过时返回现场，并把「已报」置位
    ///
    /// 已报过就返回 nil —— 间隔继续增长也不刷屏，等心跳恢复（主线程能跑心跳块）才清位。
    public mutating func takeStall(at now: UInt64) -> Stall? {
        let gapSeconds = Double(now &- lastBeatNanoseconds) / 1_000_000_000
        guard MainThreadWatchdogPolicy.isStalled(gapSeconds: gapSeconds), !reportedStall else {
            return nil
        }
        reportedStall = true
        return Stall(gapSeconds: gapSeconds, tab: tab, panelShown: panelShown,
                     indexingState: indexingState)
    }
}
