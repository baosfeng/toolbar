import Foundation
import NetworkMonitorUI

// MARK: - 额度推送回拉的放行判据

/// 断言「额度推送 → 面板通知 → 再拉额度」这条反馈边的闸门
///
/// 背景：这条边是同步闭环，空态下每轮都 emit 会无限递归把栈写爆。
/// 判据必须只在「额度页 + 不是推送引起的那一次」才放行。
func runBillingRefreshGateTests() {
    print("\n🧪 Testing BillingRefreshGate...")
    do {
        // 1. 额度页、且这次通知不是额度推送引起的 → 放行（常规内容变化要回拉一次）
        assertEqual(BillingRefreshGate.shouldPullForContentChange(isBillingTab: true,
                                                                 isPushingSnapshot: false),
                    true, "额度页的常规内容变化回拉一次")
        // 2. 额度页、且正在消费一次额度推送 → 挡住（否则 refresh → emit → 再 refresh 递归）
        assertEqual(BillingRefreshGate.shouldPullForContentChange(isBillingTab: true,
                                                                 isPushingSnapshot: true),
                    false, "由额度推送引起的那次通知不再回拉")
        // 3. 非额度页 → 一律不回拉（其它分页不该替额度页拉数据）
        assertEqual(BillingRefreshGate.shouldPullForContentChange(isBillingTab: false,
                                                                 isPushingSnapshot: false),
                    false, "非额度页不回拉额度")
        assertEqual(BillingRefreshGate.shouldPullForContentChange(isBillingTab: false,
                                                                 isPushingSnapshot: true),
                    false, "非额度页且在推送中也不回拉")
        print("✅ BillingRefreshGate works")
    }
}
