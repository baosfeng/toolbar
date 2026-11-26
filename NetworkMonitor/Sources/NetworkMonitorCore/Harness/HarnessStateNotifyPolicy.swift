import Foundation

// MARK: - 索引状态的通知节流判据

/// `HarnessUsageService.setState` 要不要通知观察者的判据（纯函数，TestRunner 直接断言）
///
/// 背景（用户原话「每次进入 Token 页都会快速地刷新一下」）：索引期间 scanner 每读 500 行
/// 就回调一次进度，旧实现每次都通知观察者 —— 一次索引 N 次进度回调就是 N 次全页 render，
/// 页头 meta 也跟着从「2246 会话」跳到「索引中 2/6 · 500 行」再跳回来。
///
/// 收敛口径两条，缺一不可：
/// 1. **状态种类变化必通知**（idle / indexing / ready / failed 互转）：种类变化才是
///    UI 该切显隐的信号（加载态 ↔ 数据态），漏掉就会出现「索引完了界面还停在骨架」。
/// 2. **同种类（纯进度）按 `interval` 合并**：进度只是同一块文字里的数字在动，
///    500ms 一次足够让人看到「在走」，又不至于每 500 行全页重排一次。
///
/// 首次通知（`lastNotifiedAt == nil`）恒放行：否则第一帧进度会被吞掉。
public enum HarnessStateNotifyPolicy {

    /// 同种类状态的合并窗口（秒）
    ///
    /// 500ms：比一次典型扫描回调（500 行 ≈ 数十毫秒到数百毫秒）更粗，
    /// 又比人眼能感知的「卡住」更细，索引进行中数字仍在动。
    public static let interval: TimeInterval = 0.5

    /// 状态种类 —— 只有它变化才必须立刻通知
    public enum Kind: Sendable, Equatable {
        case idle
        case indexing
        case ready
        case failed
    }

    /// 取状态种类
    public static func kind(of state: HarnessIndexingState) -> Kind {
        switch state {
        case .idle: return .idle
        case .indexing: return .indexing
        case .ready: return .ready
        case .failed: return .failed
        }
    }

    /// 本次状态更新是否要通知观察者
    ///
    /// - Parameters:
    ///   - previous: 上一次**已写进 currentState** 的状态（nil = 还没有过状态）
    ///   - next: 本次要写入的状态
    ///   - lastNotifiedAt: 上一次真正通知观察者的时刻（nil = 还没通知过）
    ///   - now: 本次时刻
    ///   - interval: 合并窗口（<= 0 / 非有限时回落 `interval`）
    public static func shouldNotify(previous: HarnessIndexingState?,
                                    next: HarnessIndexingState,
                                    lastNotifiedAt: Date?,
                                    now: Date,
                                    interval customInterval: TimeInterval = interval) -> Bool {
        // 种类变化：无论多快都必须通知（否则加载态 ↔ 数据态会错位）
        guard let previous, kind(of: previous) == kind(of: next) else { return true }
        guard let lastNotifiedAt else { return true }
        let window = (customInterval.isFinite && customInterval > 0) ? customInterval : interval
        let elapsed = now.timeIntervalSince(lastNotifiedAt)
        // 时钟回退（改系统时间）按「该通知」处理：否则差值恒为负会永久不通知
        guard elapsed >= 0 else { return true }
        return elapsed >= window
    }
}
