import Foundation
import NetworkMonitorUI

// MARK: - 额度格口径

/// 断言额度格的三条纯口径：告警分级、角标拼接、角标行数
///
/// 这三条原来散在视图的 update / syncResetRow 里（无法测），改自绘后抽到 BillingCellLayout；
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

    // 2. 角标拼接：同行才带分隔符
    assertEqual(BillingCellLayout.badgeText("已限流", hasReset: true, compact: false),
                "已限流 ·", "同行时角标带分隔符")
    assertEqual(BillingCellLayout.badgeText("已限流", hasReset: false, compact: false),
                "已限流", "没有重置时间时不带分隔符")
    assertEqual(BillingCellLayout.badgeText("已限流", hasReset: true, compact: true),
                "已限流", "窄格分行时不带分隔符")
    assertEqual(BillingCellLayout.badgeText(nil, hasReset: true, compact: false), nil,
                "没有角标就是 nil")

    // 3. 角标行数：窄格两行、同行一格、都没有则整行不画
    assertEqual(BillingCellLayout.footerLineCount(hasBadge: true, hasReset: true, compact: true), 2,
                "窄格角标 + 重置分两行")
    assertEqual(BillingCellLayout.footerLineCount(hasBadge: false, hasReset: true, compact: true), 1,
                "窄格只有重置时一行")
    assertEqual(BillingCellLayout.footerLineCount(hasBadge: true, hasReset: true, compact: false), 1,
                "同行时只占一行")
    assertEqual(BillingCellLayout.footerLineCount(hasBadge: false, hasReset: false, compact: false), 0,
                "都没有时整行不画")
    print("✅ BillingCellLayout works")
}