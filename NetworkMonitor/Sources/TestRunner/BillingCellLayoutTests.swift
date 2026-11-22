import Foundation
import NetworkMonitorUI

// MARK: - 额度格口径

/// 断言额度格的告警分级口径（角标拼接与角标行数随旧额度格删除）
///
/// 这条原来散在视图的 update 里（无法测），改自绘后抽到 BillingCellLayout；
/// 视图只做绘制，口径仍由这里守住。
func runBillingCellLayoutTests() {
    print("\n🧪 Testing BillingCellLayout...")

    // 1. 告警分级：<20% 红、<50% 橙、其余正常（边界取严格小于）
    assertEqual(BillingCellLayout.level(for: 0.19), .danger, "19% 走危险档")
    assertEqual(BillingCellLayout.level(for: 0.2), .warn, "恰 20% 不进危险档")
    assertEqual(BillingCellLayout.level(for: 0.49), .warn, "49% 走告警档")
    assertEqual(BillingCellLayout.level(for: 0.5), .normal, "恰 50% 回正常档")
    assertEqual(BillingCellLayout.level(for: 0), .danger, "0% 是危险档")
    assertEqual(BillingCellLayout.level(for: 1), .normal, "100% 正常")

    print("✅ BillingCellLayout works")
}