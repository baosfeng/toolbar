import Foundation
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 面板刷新策略（tick 判定链）

/// 断言 tick 的三层判定：额度 → 可见层（含 5 秒系统页闸门）→ 中频闸门
///
/// 只看「本轮要做什么」的结果结构，不启动 popover、不碰 AppKit。
/// 间隔值是 0.5 / 2 / 5 / 15 这类十进制值，等号边界有浮点误差，故统一用 ±0.1s 判定。
func runPanelRefreshPolicyTests() {
    print("\n🧪 Testing PanelRefreshPolicy...")
    let base = Date(timeIntervalSince1970: 1_700_000_000)

    func plan(tier: RenderTier,
              visible: Bool,
              tab: String = "network",
              lastMid: TimeInterval = -1_000,
              lastSystem: TimeInterval = -1_000) -> PanelRefreshPlan {
        PanelRefreshPolicy.plan(PanelRefreshInput(
            now: base,
            lastMidRefresh: base.addingTimeInterval(lastMid),
            lastSystemRefresh: base.addingTimeInterval(lastSystem),
            tier: tier,
            panelVisible: visible,
            currentTabStableID: tab))
    }

    // 1. 标准档 + 展开：三层全开
    let standardOpen = plan(tier: .standard, visible: true)
    assertEqual(standardOpen.pullsBilling, true, "标准档展开：拉额度")
    assertEqual(standardOpen.refreshesVisibleLayer, true, "标准档展开：刷新可见层")
    assertEqual(standardOpen.rendersSystemViews, true, "标准档展开：系统页闸门已到点")
    assertEqual(standardOpen.runsMidFrequency, true, "标准档展开：中频已到点")

    // 2. 标准 / 极致档收起：只停可见层，额度照拉（额度阈值提醒依赖它）
    for tier in [RenderTier.standard, .extreme] {
        let closed = plan(tier: tier, visible: false)
        assertEqual(closed.pullsBilling, true, "\(tier.displayName)档收起：仍拉额度")
        assertEqual(closed.refreshesVisibleLayer, false, "\(tier.displayName)档收起：不刷可见层")
        assertEqual(closed.rendersSystemViews, false, "\(tier.displayName)档收起：不渲染系统页")
        assertEqual(closed.runsMidFrequency, false, "\(tier.displayName)档收起：不跑中频")
    }

    // 3. 省电档收起：整轮停摆（连额度也不拉）
    let powerSaveClosed = plan(tier: .powerSave, visible: false)
    assertEqual(powerSaveClosed.pullsBilling, false, "省电档收起：连额度也不拉（停摆）")
    assertEqual(powerSaveClosed.refreshesVisibleLayer, false, "省电档收起：不刷可见层")

    // 4. 中频边界：标准 5s / 极致 2s / 省电 15s
    assertEqual(plan(tier: .standard, visible: true, lastMid: -4.9).runsMidFrequency, false,
                "标准档 4.9s<5s：中频未到点")
    assertEqual(plan(tier: .standard, visible: true, lastMid: -5.1).runsMidFrequency, true,
                "标准档 5.1s>5s：中频到点")
    assertEqual(plan(tier: .extreme, visible: true, lastMid: -1.9).runsMidFrequency, false,
                "极致档 1.9s<2s：中频未到点")
    assertEqual(plan(tier: .extreme, visible: true, lastMid: -2.1).runsMidFrequency, true,
                "极致档 2.1s>2s：中频到点")
    assertEqual(plan(tier: .powerSave, visible: true, lastMid: -14.9).runsMidFrequency, false,
                "省电档 14.9s<15s：中频未到点")
    assertEqual(plan(tier: .powerSave, visible: true, lastMid: -15.1).runsMidFrequency, true,
                "省电档 15.1s>15s：中频到点")

    // 5. 系统页 5 秒闸门：固定 5s，不随档位变
    assertEqual(plan(tier: .standard, visible: true, lastSystem: -4.9).rendersSystemViews, false,
                "标准档 4.9s<5s：系统页不渲染")
    assertEqual(plan(tier: .standard, visible: true, lastSystem: -5.1).rendersSystemViews, true,
                "标准档 5.1s>5s：系统页渲染")
    assertEqual(plan(tier: .powerSave, visible: true, lastSystem: -4.9).rendersSystemViews, false,
                "省电档同样是 5s 闸门")
    assertEqual(PanelRefreshPolicy.systemRefreshInterval, 5.0, "系统页闸门间隔固定 5 秒")

    // 6. 两道闸门互不影响：系统页到点、中频未到点
    let systemOnly = plan(tier: .standard, visible: true, lastMid: -0.5, lastSystem: -10)
    assertEqual(systemOnly.rendersSystemViews, true, "系统页到点")
    assertEqual(systemOnly.runsMidFrequency, false, "中频未到点（两个闸门各自独立）")

    // 7. 分页 / 展开态原样透传（看门狗心跳读这两个字段）
    let tokenTab = plan(tier: .standard, visible: true, tab: "token")
    assertEqual(tokenTab.currentTabStableID, "token", "分页稳定 id 透传")
    assertEqual(tokenTab.panelVisible, true, "展开态透传")
    assertEqual(tokenTab.now, base, "本轮时刻透传（回写上次刷新时刻用）")

    // 8. 分页不改变刷新层级：换页不重算节拍
    for tab in ["network", "transfer", "credits", "token", "system"] {
        let each = plan(tier: .standard, visible: true, tab: tab, lastMid: -6, lastSystem: -6)
        assertEqual(each.runsMidFrequency, true, "\(tab) 页：中频到点即刷（不因分页改变）")
        assertEqual(each.rendersSystemViews, true, "\(tab) 页：系统页闸门同样 5s")
    }

    print("✅ PanelRefreshPolicy works")
}
