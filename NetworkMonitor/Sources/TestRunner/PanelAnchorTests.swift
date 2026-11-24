import CoreGraphics
import Foundation
import NetworkMonitorUI

// MARK: - 面板锚点矩形

/// PanelAnchor 的完整契约：锚点是贴状态项**中心**的 1pt 窄矩形，中心不随按钮宽度漂移
///
/// 为什么会从「贴右边缘」改成「贴中心」：系统给 popover 画的顶端小三角恒在窗口水平中心，
/// 挪不动也改不了（用户截图实测三角 362.4pt vs 面板中心 362.5pt，差 0.1pt）。
/// 右对齐状态项右边缘时三角会偏左 —— 实测状态项 947,4.5 183x24（中心 1038）配 346 宽面板，
/// 窗口中心落在 956，三角偏 82pt，正指在「↓36K」那个字上。
///
/// 三次定位试错（都是 nmcli 连采同一进程）：
/// - 直接把 button.bounds 交给 popover → 锚点矩形随宽度变化，面板 x 跳 26pt；
/// - 「宽 320pt、贴右边缘」的大矩形 → 仍漂 10pt（越出按钮 bounds，被 AppKit 按视图边界处理）；
/// - 最终口径：宽 1pt、中心对齐 bounds.midX，窗口中心与状态项中心残差 < 0.5pt。
///
/// 坐标口径：按钮 bounds 是按钮自身坐标系（原点常为 0,0，宽度随文字变），
/// 屏幕位置由「右边缘固定在 maxX、宽度向左生长」给出，故屏幕 frame 的 minX = maxX − width。
func runPanelAnchorTests() {
    print("🧪 Testing panel anchor...")

    /// 一次实测采样的状态项几何：右边缘恒定、宽度不同
    struct Sample {
        let width: CGFloat
        let maxX: CGFloat
        var screenFrame: CGRect { CGRect(x: maxX - width, y: 0, width: width, height: 24) }
        var bounds: CGRect { CGRect(x: 0, y: 0, width: width, height: 24) }
        var anchor: CGRect { PanelAnchor.rectInScreen(buttonBounds: bounds, buttonFrameInScreen: screenFrame) }
    }

    let samples = [89, 106, 81, 95, 79, 140].map { Sample(width: CGFloat($0), maxX: 1130) }

    // 1. 锚点宽度恒为 1pt、中心对齐状态项中心
    for sample in samples {
        assertEqual(sample.anchor.midX, 1130 - sample.width / 2,
                    "按钮宽 \(sample.width)：锚点中心对齐状态项中心（实际 \(sample.anchor.midX)）")
        assertEqual(sample.anchor.width, PanelAnchor.preferredWidth,
                    "按钮宽 \(sample.width)：锚点宽度恒定 1pt（实际 \(sample.anchor.width)）")
        assertEqual(sample.anchor.height, 24, "按钮宽 \(sample.width)：锚点高度沿用按钮")
        assertEqual(sample.anchor.minY, 0, "按钮宽 \(sample.width)：锚点纵向不动")
    }

    // 2. 同一右边缘下按钮宽度变化时锚点中心跟着按钮中心走（所以面板位置必须靠 pin 冻结）
    let reference = samples[0]
    for sample in samples.dropFirst() {
        let expected = 1130 - sample.width / 2
        assertEqual(sample.anchor.midX, expected,
                    "按钮宽 \(reference.width)→\(sample.width)：锚点中心 = maxX − 宽/2（实际 \(sample.anchor.midX)）")
    }

    // 3. 锚点矩形落在屏幕内（面板靠它定位，出屏会贴边跳位）
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    for sample in samples {
        assertEqual(screen.contains(sample.anchor), true,
                    "按钮宽 \(sample.width)：锚点 \(sample.anchor) 落在屏幕内")
    }

    // 4. 整个按钮平移时锚点中心同比平移
    let narrow = Sample(width: 89, maxX: 1130).anchor
    let shifted = Sample(width: 89, maxX: 1330).anchor
    assertEqual(shifted.midX - narrow.midX, 200, "按钮右移 200pt：锚点中心同比右移 200pt")
    assertEqual(shifted.width, narrow.width, "平移时锚点宽度仍恒定")

    // 5. 窄矩形必须在按钮 bounds 内，且中心落在按钮中心
    for sample in samples {
        assertEqual(sample.anchor.width <= sample.bounds.width, true,
                    "按钮宽 \(sample.width)：锚点宽度不越出按钮 bounds")
        assertEqual(abs(sample.anchor.midX - sample.screenFrame.midX) < 0.01, true,
                    "按钮宽 \(sample.width)：锚点中心落在按钮屏幕中心")
    }

    // 6. 退化入参：宽度 <= 0 回落 1pt
    let oddBounds = CGRect(x: 0, y: 0, width: 89, height: 24)
    assertEqual(PanelAnchor.rect(for: oddBounds, width: 0).width, PanelAnchor.preferredWidth,
                "宽度 0 → 回落 1pt")
    assertEqual(PanelAnchor.rect(for: oddBounds, width: -10).width, PanelAnchor.preferredWidth,
                "宽度负数 → 回落 1pt")
    assertEqual(PanelAnchor.rect(for: oddBounds, width: 0).midX, oddBounds.midX,
                "退化入参下仍对齐中心")

    // 7. 钉住目标：不同按钮宽度 → 窗口中心都要落在状态项中心
    let visible = CGRect(x: 0, y: 0, width: 1512, height: 982)
    for width in [79, 89, 97, 106] as [CGFloat] {
        let maxX = 1130 as CGFloat
        let center = maxX - width / 2
        let x = PanelAnchor.pinnedX(panelWidth: 346,
                                    statusItemCenterX: center,
                                    visibleMinX: visible.minX,
                                    visibleMaxX: visible.maxX)
        assertEqual(x, center - 173,
                    "按钮宽 \(width)：面板以状态项中心居中（目标 x = center − 173）")
        assertEqual(x + 346 / 2, center, "按钮宽 \(width)：窗口中心 == 状态项中心")
        assertEqual(visible.minX...visible.maxX ~= x, true, "按钮宽 \(width)：目标 x 落在屏幕内")
    }

    // 8. 钉住目标的边界
    assertEqual(PanelAnchor.pinnedX(panelWidth: 2000, statusItemCenterX: 1038,
                                    visibleMinX: 0, visibleMaxX: 1512), 0,
                "面板比屏幕宽：贴左边界")
    assertEqual(PanelAnchor.pinnedX(panelWidth: 346, statusItemCenterX: 1700,
                                    visibleMinX: 0, visibleMaxX: 1512), 1166,
                "状态项越出屏幕右侧：目标 x 夹到 1512 − 346")
    assertEqual(PanelAnchor.pinnedX(panelWidth: 0, statusItemCenterX: 1038,
                                    visibleMinX: 0, visibleMaxX: 1512), 0,
                "面板宽度非法：回落左边界")

    // 9. 纵向钉顶边
    let visibleY = CGRect(x: 0, y: 0, width: 1512, height: 960)
    let pinnedTop: CGFloat = 900
    var topEdges: [CGFloat] = []
    for height in [350, 506, 537, 546] as [CGFloat] {
        let originY = PanelAnchor.pinnedOriginY(panelHeight: height,
                                                panelTopEdge: pinnedTop,
                                                visibleMinY: visibleY.minY,
                                                visibleMaxY: visibleY.maxY)
        topEdges.append(originY + height)
        assertEqual(originY, pinnedTop - height,
                    "高度 " + String(describing: height) + "：原点 y = 记住的顶边 − 高度")
        assertEqual(originY >= visibleY.minY, true,
                    "高度 " + String(describing: height) + "：原点不越出可视区下沿")
    }
    assertEqual(Set(topEdges).count, 1,
                "高度在 350…546 之间变化时顶边只有一个取值")

    // 10. 纵向边界
    assertEqual(PanelAnchor.pinnedOriginY(panelHeight: 300, panelTopEdge: 1200,
                                          visibleMinY: 0, visibleMaxY: 960), 660,
                "顶边越出屏幕上沿：先夹到 960，再算原点 960 − 300")
    assertEqual(PanelAnchor.pinnedOriginY(panelHeight: 1200, panelTopEdge: 900,
                                          visibleMinY: 0, visibleMaxY: 960), 0,
                "面板比可视区还高：原点贴可视区下沿")
    assertEqual(PanelAnchor.pinnedOriginY(panelHeight: 0, panelTopEdge: 900,
                                          visibleMinY: 0, visibleMaxY: 960), 0,
                "高度非法：回落可视区下沿")

    // 11. 横向 + 纵向组合：切多高的页，窗口中心 x 与顶边都不动
    var topCenters: [CGFloat] = []
    for height in [350, 506, 537, 546] as [CGFloat] {
        let x = PanelAnchor.pinnedX(panelWidth: 346, statusItemCenterX: 1038,
                                    visibleMinX: visibleY.minX, visibleMaxX: visibleY.maxX)
        let y = PanelAnchor.pinnedOriginY(panelHeight: height,
                                          panelTopEdge: pinnedTop,
                                          visibleMinY: visibleY.minY,
                                          visibleMaxY: visibleY.maxY)
        topCenters.append(x + 346 / 2 + (y + height))
    }
    assertEqual(Set(topCenters).count, 1,
                "高度 350…546 变化时「窗口中心 x + 顶边 y」恒定")

    // 12. 按钮 bounds 原点不在 (0,0) 时同样只锁中心
    let offsetBounds = CGRect(x: 12, y: 3, width: 106, height: 24)
    let offsetAnchor = PanelAnchor.rect(for: offsetBounds)
    assertEqual(offsetAnchor.midX, offsetBounds.midX, "非零原点：锚点中心仍对齐按钮中心")
    assertEqual(offsetAnchor.minY, offsetBounds.minY, "非零原点：纵向沿用按钮")

    // 13. 纠正目标：横向随时可算，纵向要有锁定的顶边才算
    let unlocked = PanelAnchor.pinTarget(panelFrame: CGRect(x: 955, y: 524, width: 346, height: 425),
                                         statusItemCenterX: 1038,
                                         lockedTopEdge: nil,
                                         visible: visible)
    assertEqual(unlocked.x, 865, "未锁顶边：横向照样算出居中目标 1038 − 173")
    assertEqual(unlocked.y, nil, "未锁顶边：纵向不给目标")

    let locked = PanelAnchor.pinTarget(panelFrame: CGRect(x: 955, y: 524, width: 346, height: 425),
                                       statusItemCenterX: 1038,
                                       lockedTopEdge: 949,
                                       visible: visible)
    assertEqual(locked.x, 865, "已锁顶边：横向目标不变")
    assertEqual(locked.y, 524, "已锁顶边：原点 y = 949 − 425")

    // 14. 同一顶边下切不同高度的页：窗口中心 x 恒定
    var centers: [CGFloat] = []
    for height in [345, 425, 506, 546] as [CGFloat] {
        let target = PanelAnchor.pinTarget(panelFrame: CGRect(x: 955, y: 300, width: 346, height: height),
                                           statusItemCenterX: 1039,
                                           lockedTopEdge: 949,
                                           visible: visible)
        assertEqual(target.x, 866, "高度 " + String(describing: height) + "：横向目标恒定")
        centers.append(target.x + 346 / 2)
    }
    assertEqual(Set(centers).count, 1,
                "高度 345…546 变化时窗口中心恒定")

    // 15. 系统 beak 恒在窗口中心：这条就是「窗口中心 = 状态项中心」的直接依据
    let itemCenter: CGFloat = 1038
    let panelX = PanelAnchor.pinnedX(panelWidth: 346, statusItemCenterX: itemCenter,
                                     visibleMinX: 0, visibleMaxX: 1512)
    assertEqual(panelX + 173, itemCenter, "beak 在窗口中心 ⇒ 三角落在状态项中心")

    print("✅ PanelAnchor works")
}
