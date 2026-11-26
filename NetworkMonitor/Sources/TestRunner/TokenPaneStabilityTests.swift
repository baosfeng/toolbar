import Foundation
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - Token 页「不再闪一下」的三条判据

/// 覆盖用户原话「每次进入 Token 页，这个会话都会快速地刷新一下」背后的三条判据：
/// 1. `HarnessStateNotifyPolicy` —— 状态广播节流（每 500 行一次全页 render 的来源）；
/// 2. `TokenPaneRefreshGate` —— 切页新鲜度闸门（一次切页排两次请求的来源）；
/// 3. `TokenPaneDisplayPolicy` —— 「索引中 …」延迟显形与空帧顶住（文字那一格跳变的来源）。
///
/// 三条都是纯函数，所以能在这里逐条锁死边界：种类变化 / 首次 / 时钟回退 / 窗口边界。
func runTokenPaneStabilityTests() {
    print("\n🧪 Testing Token 页进入抖动（状态节流 / 切页闸门 / 延迟显形）...")
    testStateNotifyKindChange()
    testStateNotifyThrottle()
    testStateNotifyClockRollback()
    testRefreshGateFreshness()
    testRefreshGateClockRollback()
    testIndexNoteDelay()
    testRetainedFrame()
    print("✅ Token 页进入抖动（三条判据）works")
}

// MARK: - 状态广播节流

private func testStateNotifyKindChange() {
    let now = Date(timeIntervalSince1970: 1_000)
    let progress1 = HarnessIndexProgress(completedFiles: 0, totalFiles: 4, currentFile: "a", parsedSessions: 0)
    let progress2 = HarnessIndexProgress(completedFiles: 1, totalFiles: 4, currentFile: "b", parsedSessions: 1)

    // 种类变化必通知：哪怕距上次通知只有 1ms（否则加载态 ↔ 数据态会错位）
    assertEqual(HarnessStateNotifyPolicy.shouldNotify(previous: .idle, next: .indexing(progress1),
                                                      lastNotifiedAt: now, now: now), true,
                "idle → indexing 必通知")
    assertEqual(HarnessStateNotifyPolicy.shouldNotify(previous: .indexing(progress1), next: .ready,
                                                      lastNotifiedAt: now, now: now), true,
                "indexing → ready 必通知")
    assertEqual(HarnessStateNotifyPolicy.shouldNotify(previous: .ready, next: .failed(message: "x"),
                                                      lastNotifiedAt: now, now: now), true,
                "ready → failed 必通知")
    assertEqual(HarnessStateNotifyPolicy.kind(of: .indexing(progress1)),
                HarnessStateNotifyPolicy.kind(of: .indexing(progress2)),
                "两条进度属同一「种类」")
}

private func testStateNotifyThrottle() {
    let base = Date(timeIntervalSince1970: 2_000)
    let progress1 = HarnessIndexProgress(completedFiles: 0, totalFiles: 4, currentFile: "a", parsedSessions: 0)
    let progress2 = HarnessIndexProgress(completedFiles: 1, totalFiles: 4, currentFile: "b", parsedSessions: 1)

    assertEqual(HarnessStateNotifyPolicy.shouldNotify(previous: .indexing(progress1),
                                                      next: .indexing(progress2),
                                                      lastNotifiedAt: nil, now: base), true,
                "首次通知恒放行（否则第一帧进度会被吞掉）")
    assertEqual(HarnessStateNotifyPolicy.shouldNotify(previous: .indexing(progress1),
                                                      next: .indexing(progress2),
                                                      lastNotifiedAt: base, now: base), false,
                "同一时刻的纯进度更新被合并（旧实现每次 500 行都广播）")
    assertEqual(HarnessStateNotifyPolicy.shouldNotify(previous: .indexing(progress1),
                                                      next: .indexing(progress2),
                                                      lastNotifiedAt: base,
                                                      now: base.addingTimeInterval(0.2)), false,
                "200ms 内的进度更新仍被合并")
    assertEqual(HarnessStateNotifyPolicy.shouldNotify(previous: .indexing(progress1),
                                                      next: .indexing(progress2),
                                                      lastNotifiedAt: base,
                                                      now: base.addingTimeInterval(0.5)), true,
                "满 500ms 放行一次（进度数字仍在动）")

    // 一次索引 N 次进度回调 → 广播次数按 500ms 窗口收敛
    var notified = 0
    var last: Date?
    let callbackInterval = 0.05   // 500 行 ≈ 50ms（保守估计）
    for step in 0..<100 {
        let now = base.addingTimeInterval(Double(step) * callbackInterval)
        let next = HarnessIndexProgress(completedFiles: step, totalFiles: 100,
                                        currentFile: "f", parsedSessions: step)
        if HarnessStateNotifyPolicy.shouldNotify(previous: .indexing(progress1), next: .indexing(next),
                                                 lastNotifiedAt: last, now: now) {
            notified += 1
            last = now
        }
    }
    // 100 次回调覆盖 5s，窗口 0.5s → 首帧 1 次 + 每 0.5s 一次 ≈ 11 次（不是 100 次）
    assertEqual(notified <= 12, true, "100 次进度回调的广播次数应被压到 ≤12 次（实测 \(notified) 次）")
    assertEqual(notified >= 10, true, "但也不该压成 1 次（进度要能看见在动，实测 \(notified) 次）")
    print("   · 100 次进度回调 → \(notified) 次通知（改前 = 100 次）")

    // 自定义窗口 <= 0 / 非有限时回落默认值，不把通知全关掉
    assertEqual(HarnessStateNotifyPolicy.shouldNotify(previous: .indexing(progress1),
                                                      next: .indexing(progress2),
                                                      lastNotifiedAt: base,
                                                      now: base.addingTimeInterval(0.6),
                                                      interval: 0), true,
                "窗口 <= 0 时回落默认 500ms")
    assertEqual(HarnessStateNotifyPolicy.shouldNotify(previous: .indexing(progress1),
                                                      next: .indexing(progress2),
                                                      lastNotifiedAt: base,
                                                      now: base.addingTimeInterval(0.6),
                                                      interval: .infinity), true,
                "窗口非有限时回落默认 500ms")
}

private func testStateNotifyClockRollback() {
    let base = Date(timeIntervalSince1970: 3_000)
    let progress = HarnessIndexProgress(completedFiles: 1, totalFiles: 4, currentFile: "a", parsedSessions: 1)
    assertEqual(HarnessStateNotifyPolicy.shouldNotify(previous: .indexing(progress),
                                                      next: .indexing(progress),
                                                      lastNotifiedAt: base,
                                                      now: base.addingTimeInterval(-10)), true,
                "时钟回退按「该通知」处理（否则差值恒为负会永久不通知）")
}

// MARK: - 切页新鲜度闸门

private func testRefreshGateFreshness() {
    let base = Date(timeIntervalSince1970: 4_000)
    assertEqual(TokenPaneRefreshGate.shouldRefresh(indexedAt: nil, requestedAt: nil, now: base), true,
                "从没扫过 → 必须扫")
    assertEqual(TokenPaneRefreshGate.shouldRefresh(indexedAt: base, requestedAt: nil, now: base), false,
                "索引完成于同一时刻 → 刚扫完，不重复扫（这是「切页不要闪」的第一道闸）")
    assertEqual(TokenPaneRefreshGate.shouldRefresh(indexedAt: base, requestedAt: nil,
                                                   now: base.addingTimeInterval(30)), false,
                "30s 前刚扫完 → 跳过（改前每次切页都重扫）")
    assertEqual(TokenPaneRefreshGate.shouldRefresh(indexedAt: base, requestedAt: nil,
                                                   now: base.addingTimeInterval(60)), true,
                "满 60s → 该扫")
    assertEqual(TokenPaneRefreshGate.shouldRefresh(indexedAt: base, requestedAt: nil,
                                                   now: base.addingTimeInterval(59.9)), false,
                "59.9s 仍不扫（窗口边界不提前）")

    // 索引跑到一半：lastScanAt 还是上一轮旧值，靠「上次请求时刻」挡住连点切页
    let staleIndex = base.addingTimeInterval(-600)
    let justRequested = base.addingTimeInterval(-1)
    assertEqual(TokenPaneRefreshGate.shouldRefresh(indexedAt: staleIndex, requestedAt: justRequested,
                                                   now: base), false,
                "1 秒前刚排过请求 → 即使索引完成时刻很旧也不再排第二次")
    assertEqual(TokenPaneRefreshGate.lastActivity(indexedAt: staleIndex, requestedAt: justRequested),
                justRequested, "取两个时刻里更晚的那个")
    assertEqual(TokenPaneRefreshGate.lastActivity(indexedAt: nil, requestedAt: nil) == nil, true,
                "都没有 → nil（视作从未扫过）")
    assertEqual(TokenPaneRefreshGate.lastActivity(indexedAt: base, requestedAt: nil), base,
                "只有索引完成时刻时用它")
    assertEqual(TokenPaneRefreshGate.shouldRefresh(indexedAt: base, requestedAt: nil,
                                                   now: base, interval: 0), false,
                "窗口 <= 0 时回落 60s（同一时刻仍不刷，而不是「永远该刷」）")
    assertEqual(TokenPaneRefreshGate.shouldRefresh(indexedAt: base, requestedAt: nil,
                                                   now: base, interval: 0), 
                TokenPaneRefreshGate.shouldRefresh(indexedAt: base, requestedAt: nil,
                                                   now: base, interval: MenuBarTokenRefresh.interval),
                "窗口 <= 0 的回落值等于菜单栏那档 60s（两条路径同一口径）")
    assertEqual(MenuBarTokenRefresh.interval, TokenPaneRefreshGate.shouldRefresh(indexedAt: base,
                                                                                 requestedAt: nil,
                                                                                 now: base.addingTimeInterval(60),
                                                                                 interval: 60) ? 60.0 : -1.0,
                "满 60s 时该刷（显式传菜单栏那档间隔时口径一致）")
}

private func testRefreshGateClockRollback() {
    let base = Date(timeIntervalSince1970: 5_000)
    assertEqual(TokenPaneRefreshGate.shouldRefresh(indexedAt: base, requestedAt: nil,
                                                   now: base.addingTimeInterval(-30)), true,
                "时钟回退按「该刷新」处理")
}

// MARK: - 延迟显形

private func testIndexNoteDelay() {
    let base = Date(timeIntervalSince1970: 6_000)
    assertEqual(TokenPaneDisplayPolicy.showsIndexNote(isIndexing: false, startedAt: base, now: base), false,
                "没在索引 → 不显示进度文案")
    assertEqual(TokenPaneDisplayPolicy.showsIndexNote(isIndexing: true, startedAt: base, now: base), false,
                "索引刚开始 → 不把「2246 会话」改写成「索引中 …」（这一下就是用户看到的闪）")
    assertEqual(TokenPaneDisplayPolicy.showsIndexNote(isIndexing: true, startedAt: base,
                                                      now: base.addingTimeInterval(0.99)), false,
                "0.99s 仍在忍（快速索引全程不显形）")
    assertEqual(TokenPaneDisplayPolicy.showsIndexNote(isIndexing: true, startedAt: base,
                                                      now: base.addingTimeInterval(1.0)), true,
                "满 1s 才显形（慢索引需要让人知道在动）")
    assertEqual(TokenPaneDisplayPolicy.showsIndexNote(isIndexing: true, startedAt: nil, now: base), false,
                "缺起始时刻按「刚开始」处理，不显示")
    assertEqual(TokenPaneDisplayPolicy.showsIndexNote(isIndexing: true, startedAt: base,
                                                      now: base.addingTimeInterval(-5)), false,
                "时钟回退不产生显形")
    assertEqual(TokenPaneDisplayPolicy.indexingElapsed(startedAt: nil, now: base), 0,
                "缺起点 = 已持续 0 秒")
    assertEqual(TokenPaneDisplayPolicy.indexNoteDelay, 1.0, "延迟常量固定 1s（验收核心：快速索引零跳变）")
}

private func testRetainedFrame() {
    assertEqual(TokenPaneDisplayPolicy.prefersRetainedFrame(isEmpty: true, isIndexing: true,
                                                            hasRetainedContent: true), true,
                "空帧 + 索引中 + 有上一帧 → 顶住内容（不切骨架）")
    assertEqual(TokenPaneDisplayPolicy.prefersRetainedFrame(isEmpty: true, isIndexing: true,
                                                            hasRetainedContent: false), false,
                "首轮冷启（从没见过数据）→ 走骨架")
    assertEqual(TokenPaneDisplayPolicy.prefersRetainedFrame(isEmpty: true, isIndexing: false,
                                                            hasRetainedContent: true), false,
                "不是索引中（例如真没数据）→ 老实显示空态")
    assertEqual(TokenPaneDisplayPolicy.prefersRetainedFrame(isEmpty: false, isIndexing: true,
                                                            hasRetainedContent: true), false,
                "本来就有数据 → 不需要顶，正常渲染")
}
