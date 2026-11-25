import Foundation

// MARK: - Token 页状态呈现判据（纯逻辑）

/// 索引期间「不该闪一下」的两条呈现判据（TestRunner 直接断言）
///
/// 用户原话：「每次进入 Token 页，这个会话都会快速地刷新一下」。主因是每个进度回调都广播
/// 一次全页 render（见 `HarnessStateNotifyPolicy`），此外还有两处一跳就看得见：
/// 1. **页头 meta 位**从「2246 会话」改写成「索引中 2/6 · 500 行」再改回来；
/// 2. **索引把快照推成空帧**（重扫先清索引）时，整屏从内容切成骨架，数据回来再切回去。
///
/// 两条判据都给「先忍一下」的口径：快的索引不该产生任何可见跳变，慢的索引才让它显形。
public enum TokenPaneDisplayPolicy {

    /// 页头 meta 从「N 会话」改成「索引中 …」前的延迟（秒）
    ///
    /// 1.0s：一轮无变更的增量索引远快于此，完全不显示；真的在扫才会显形，
    /// 那时用户确实需要看见「它在动」。
    public static let indexNoteDelay: TimeInterval = 1.0

    /// 索引已持续多久（起点缺失 = 0，即「刚看到」，不给显示）
    public static func indexingElapsed(startedAt: Date?, now: Date) -> TimeInterval {
        guard let startedAt else { return 0 }
        let elapsed = now.timeIntervalSince(startedAt)
        // 时钟回退按「刚开始」处理：宁可晚一点显形，也不要负延迟导致永不显示
        return elapsed >= 0 ? elapsed : 0
    }

    /// 页头 meta 位是否该换成「索引中 …」
    ///
    /// - Parameters:
    ///   - isIndexing: 当前快照是否处于 indexing
    ///   - startedAt: 本轮索引第一次被看到的时刻（nil = 没在索引）
    ///   - now: 本次渲染时刻
    public static func showsIndexNote(isIndexing: Bool, startedAt: Date?, now: Date,
                                      delay: TimeInterval = indexNoteDelay) -> Bool {
        guard isIndexing else { return false }
        let window = (delay.isFinite && delay >= 0) ? delay : indexNoteDelay
        return indexingElapsed(startedAt: startedAt, now: now) >= window
    }

    /// 索引把快照推成空帧时，是否该拿上一帧内容顶住（true = 不切骨架 / 空态）
    ///
    /// 只有「本次是索引中 且 曾经有过内容」才顶住：首轮冷启（从没见过数据）必须走骨架，
    /// 那时顶无可顶，而骨架本来就是这一屏该有的样子。
    public static func prefersRetainedFrame(isEmpty: Bool,
                                            isIndexing: Bool,
                                            hasRetainedContent: Bool) -> Bool {
        isEmpty && isIndexing && hasRetainedContent
    }
}
