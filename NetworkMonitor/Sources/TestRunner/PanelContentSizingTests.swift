import Foundation
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 面板高度重算判定

/// 断言高度重算的两道闸门：签名（分页 + 当前页可交互行数）与合并节流，以及 force 穿透
///
/// 节流值 0.2 / 0.35 / 0.8 不是二进制精确值，等号边界有浮点误差，故：
/// - 边界用 ±1ms；
/// - 延迟量换算成毫秒整数再比对，不直接比较 Double。
func runPanelContentSizingTests() {
    print("\n🧪 Testing PanelContentSizing...")
    let base = Date(timeIntervalSince1970: 1_700_000_000)

    func decide(tier: RenderTier,
                signature: String = "network#3",
                lastSignature: String = "network#3",
                elapsed: TimeInterval = 0,
                force: Bool = false) -> PanelContentSizingDecision {
        PanelContentSizing.decide(now: base,
                                  lastCheck: base.addingTimeInterval(-elapsed),
                                  signature: signature,
                                  lastSignature: lastSignature,
                                  force: force,
                                  tier: tier)
    }

    /// 动作的可断言文本：延迟换算成毫秒整数（避免 Double 等号比较）
    func label(_ action: PanelContentSizingAction) -> String {
        switch action {
        case .skip: return "skip"
        case .deferUntil(let delay): return "defer(\(Int((delay * 1000).rounded()))ms)"
        case .recalculate: return "recalculate"
        }
    }

    // 1. 三档节流值
    assertEqual(PanelContentSizing.throttleInterval(for: .standard), 0.35, "标准档 0.35s")
    assertEqual(PanelContentSizing.throttleInterval(for: .extreme), 0.2, "极致档 0.2s")
    assertEqual(PanelContentSizing.throttleInterval(for: .powerSave), 0.8, "省电档 0.8s")

    // 2. 签名不变 → 一次布局都不跑（三档一致，且与距上次多久无关）
    for tier in RenderTier.allCases {
        let skipped = decide(tier: tier, elapsed: 10)
        assertEqual(label(skipped.action), "skip", "\(tier.displayName)档：签名不变不重算")
        assertEqual(skipped.throttleInterval, PanelContentSizing.throttleInterval(for: tier),
                    "\(tier.displayName)档：返回值带上生效节流值")
    }

    // 3. 签名变了且在窗口外 → 立刻重算
    assertEqual(label(decide(tier: .standard, signature: "system#5", elapsed: 1).action),
                "recalculate", "标准档：签名变了且窗口外 → 重算")
    assertEqual(label(decide(tier: .extreme, signature: "system#5", elapsed: 0.5).action),
                "recalculate", "极致档：0.5s>0.2s → 重算")
    assertEqual(label(decide(tier: .powerSave, signature: "system#5", elapsed: 1).action),
                "recalculate", "省电档：1s>0.8s → 重算")

    // 4. 签名变了但还在窗口内 → 合并成一次补算，延迟 = 间隔 - 已过时间
    assertEqual(label(decide(tier: .standard, signature: "system#5", elapsed: 0.1).action),
                "defer(250ms)", "标准档：窗口内合并（0.35-0.1）")
    assertEqual(label(decide(tier: .extreme, signature: "system#5", elapsed: 0.1).action),
                "defer(100ms)", "极致档：窗口内合并（0.2-0.1）")
    assertEqual(label(decide(tier: .powerSave, signature: "system#5", elapsed: 0.5).action),
                "defer(300ms)", "省电档：窗口内合并（0.8-0.5）")

    // 5. 边界：刚过窗口就重算，差一点仍在窗口内（±1ms 规避浮点误差）
    assertEqual(label(decide(tier: .standard, signature: "system#5", elapsed: 0.351).action),
                "recalculate", "标准档：略超 0.35s 即重算")
    assertEqual(label(decide(tier: .standard, signature: "system#5", elapsed: 0.349).action),
                "defer(1ms)", "标准档：略差 0.35s 仍合并")

    // 6. force 穿透两道闸门：签名不变 + 窗口内也立刻重算，并带回生效节流值
    for tier in RenderTier.allCases {
        let forced = decide(tier: tier, elapsed: 0, force: true)
        assertEqual(label(forced.action), "recalculate",
                    "\(tier.displayName)档：force 穿透签名与节流")
        assertEqual(forced.throttleInterval, PanelContentSizing.throttleInterval(for: tier),
                    "\(tier.displayName)档：force 也报告生效节流值")
    }

    // 7. 时钟被改回（elapsed 为负）→ 当作没到点合并补算，而不是立刻重算或卡死
    assertEqual(label(decide(tier: .standard, signature: "system#5", elapsed: -5).action),
                "defer(5350ms)", "时钟回退：按未到点合并补算")

    print("✅ PanelContentSizing works")
}
