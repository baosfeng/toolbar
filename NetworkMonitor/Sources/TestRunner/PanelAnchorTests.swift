import CoreGraphics
import Foundation
import NetworkMonitorUI

// MARK: - 面板锚点矩形

/// PanelAnchor 的完整契约：锚点是贴状态项**右边缘**的 1pt 窄矩形，中心不随按钮宽度漂移
///
/// 实测背景（nmcli 连采同一进程）：状态项 x=1039 w=91 / x=1035 w=95 / x=1049 w=81，
/// 三者 maxX 恒为 1130（右侧系统图标固定、宽度向左生长）。
/// - 改造前把 button.bounds 交给 popover：锚点中心 = bounds.midX 跟着宽度跑，面板 x 跳 26pt；
/// - 改用「宽 320pt、贴右边缘」的大矩形：仍漂 10pt（越出按钮 bounds，被 AppKit 按视图边界处理）；
/// - 最终口径：宽 1pt、贴右边缘，中心 = maxX − 0.5，与宽度彻底解耦。
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

    // 1. 锚点宽度恒为 1pt、右边缘对齐状态项右边缘
    for sample in samples {
        assertEqual(sample.anchor.maxX, 1130,
                    "按钮宽 \(sample.width)：锚点 maxX 对齐状态项右边缘 1130（实际 \(sample.anchor.maxX)）")
        assertEqual(sample.anchor.width, PanelAnchor.preferredWidth,
                    "按钮宽 \(sample.width)：锚点宽度恒定 1pt（实际 \(sample.anchor.width)）")
        assertEqual(sample.anchor.height, 24, "按钮宽 \(sample.width)：锚点高度沿用按钮")
        assertEqual(sample.anchor.minY, 0, "按钮宽 \(sample.width)：锚点纵向不动")
    }

    // 2. 核心判据：按钮宽度变化（含 ≥10pt）时锚点中心变化为 0
    let reference = samples[0].anchor.midX
    for sample in samples.dropFirst() {
        let drift = abs(sample.anchor.midX - reference)
        assertEqual(drift, 0,
                    "按钮宽 \(samples[0].width)→\(sample.width)：锚点中心漂移 0pt（实际 \(drift)pt）")
    }
    for width in [80, 89, 106, 140] as [CGFloat] {
        let buttonBounds = CGRect(x: 0, y: 0, width: width, height: 24)
        let screen = CGRect(x: 1130 - width, y: 0, width: width, height: 24)
        let anchor = PanelAnchor.rectInScreen(buttonBounds: buttonBounds, buttonFrameInScreen: screen)
        assertEqual(anchor.midX, 1129.5,
                    "按钮宽 \(width)：锚点中心恒为 1130−0.5=1129.5（实际 \(anchor.midX)）")
    }

    // 3. 锚点矩形落在屏幕内（面板靠它定位，出屏会贴边跳位）
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    for sample in samples {
        assertEqual(screen.contains(sample.anchor), true,
                    "按钮宽 \(sample.width)：锚点 \(sample.anchor) 落在屏幕 \(screen) 内")
    }

    // 4. 右边缘本身移动时（用户改菜单栏指标）锚点跟着右边缘走，不跟着宽度走
    let narrow = Sample(width: 89, maxX: 1130).anchor
    let shifted = Sample(width: 140, maxX: 1330).anchor
    assertEqual(shifted.maxX - narrow.maxX, 200, "右边缘右移 200pt：锚点跟着右移 200pt")
    assertEqual(shifted.midX - narrow.midX, 200, "右边缘右移 200pt：锚点中心同比右移")
    assertEqual(shifted.width, narrow.width, "右边缘右移时锚点宽度仍恒定")

    // 5. 窄矩形必须在按钮 bounds 内（越界大矩形会被 AppKit 按视图边界处理，实测仍漂 10pt）
    for sample in samples {
        assertEqual(sample.anchor.width <= sample.bounds.width, true,
                    "按钮宽 \(sample.width)：锚点宽度不越出按钮 bounds")
    }

    // 6. 退化入参：宽度 <= 0 回落 1pt（不产生零宽 / 负宽矩形）
    let oddBounds = CGRect(x: 0, y: 0, width: 89, height: 24)
    assertEqual(PanelAnchor.rect(for: oddBounds, width: 0).width, PanelAnchor.preferredWidth,
                "宽度 0 → 回落 1pt")
    assertEqual(PanelAnchor.rect(for: oddBounds, width: -10).width, PanelAnchor.preferredWidth,
                "宽度负数 → 回落 1pt")
    assertEqual(PanelAnchor.rect(for: oddBounds, width: 0).maxX, oddBounds.maxX,
                "退化入参下仍对齐右边缘")

    // 7. 钉住目标：不同按钮宽度（79/89/97）→ 目标 x 完全相同（右对齐状态项右边缘）
    let visible = CGRect(x: 0, y: 0, width: 1512, height: 982)
    var pinnedXs: [CGFloat] = []
    for width in [79, 89, 97, 106] as [CGFloat] {
        let maxX = 1130 as CGFloat
        let x = PanelAnchor.pinnedX(panelWidth: 346,
                                    statusItemMaxX: maxX,
                                    visibleMinX: visible.minX,
                                    visibleMaxX: visible.maxX)
        pinnedXs.append(x)
        assertEqual(x, maxX - 346,
                    "按钮宽 \(width)：面板右对齐状态项右边缘（目标 x = \(maxX) − 346）")
        assertEqual(visible.minX...visible.maxX ~= x, true, "按钮宽 \(width)：目标 x 落在屏幕内")
    }
    assertEqual(Set(pinnedXs).count, 1, "按钮宽度变化时目标 x 只有一个取值")

    // 8. 钉住目标的边界：面板比屏幕还宽时贴左边界，接近右边缘时向右夹取不越界
    assertEqual(PanelAnchor.pinnedX(panelWidth: 2000, statusItemMaxX: 1130,
                                    visibleMinX: 0, visibleMaxX: 1512), 0,
                "面板比屏幕宽：贴左边界")
    assertEqual(PanelAnchor.pinnedX(panelWidth: 346, statusItemMaxX: 1700,
                                    visibleMinX: 0, visibleMaxX: 1512), 1166,
                "状态项越出屏幕右侧：目标 x 夹到 1512 − 346")
    assertEqual(PanelAnchor.pinnedX(panelWidth: 0, statusItemMaxX: 1130,
                                    visibleMinX: 0, visibleMaxX: 1512), 0,
                "面板宽度非法：回落左边界")

    // 9. 纵向钉顶边：同一组实测高度下，目标顶边恒定、原点 y 只在屏幕边界处夹取
    //    现场（nmcli 连采同一进程，切 tab 时底边恒 579）：h=350→顶边 229 / h=506→73 / h=537→42
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
                    "高度 " + String(describing: height) + "：原点 y = 记住的顶边 − 高度（面板向下长）")
        assertEqual(originY >= visibleY.minY, true,
                    "高度 " + String(describing: height) + "：原点不越出可视区下沿")
    }
    assertEqual(Set(topEdges).count, 1,
                "高度在 350…546 之间变化时顶边只有一个取值（实际 " + String(describing: topEdges) + "）")

    // 10. 纵向边界：顶边跑到屏幕外要夹回可视区上沿；面板比可视区还高时贴下沿
    assertEqual(PanelAnchor.pinnedOriginY(panelHeight: 300, panelTopEdge: 1200,
                                          visibleMinY: 0, visibleMaxY: 960), 660,
                "顶边越出屏幕上沿：先夹到 960，再算原点 960 − 300")
    assertEqual(PanelAnchor.pinnedOriginY(panelHeight: 1200, panelTopEdge: 900,
                                          visibleMinY: 0, visibleMaxY: 960), 0,
                "面板比可视区还高：原点贴可视区下沿")
    assertEqual(PanelAnchor.pinnedOriginY(panelHeight: 0, panelTopEdge: 900,
                                          visibleMinY: 0, visibleMaxY: 960), 0,
                "高度非法：回落可视区下沿")

    // 11. 横向 + 纵向组合：面板右上角恒定（切多高的页，右上角都不动）
    var topRightCorners: [CGPoint] = []
    for height in [350, 506, 537, 546] as [CGFloat] {
        let x = PanelAnchor.pinnedX(panelWidth: 346, statusItemMaxX: 1130,
                                    visibleMinX: visibleY.minX, visibleMaxX: visibleY.maxX)
        let y = PanelAnchor.pinnedOriginY(panelHeight: height,
                                          panelTopEdge: pinnedTop,
                                          visibleMinY: visibleY.minY,
                                          visibleMaxY: visibleY.maxY)
        topRightCorners.append(CGPoint(x: x + 346, y: y + height))
    }
    let cornerKeys = Set(topRightCorners.map { "\($0.x)|$0.y" })
    assertEqual(cornerKeys.count, 1,
                "高度 350…546 变化时右上角恒定（实际 " + String(describing: topRightCorners) + "）")

    // 12. 按钮 bounds 原点不在 (0,0) 时同样只锁右边缘（NSPopover 用视图坐标系）
    let offsetBounds = CGRect(x: 12, y: 3, width: 106, height: 24)
    let offsetAnchor = PanelAnchor.rect(for: offsetBounds)
    assertEqual(offsetAnchor.maxX, offsetBounds.maxX, "非零原点：锚点右边缘仍对齐按钮右边缘")
    assertEqual(offsetAnchor.minY, offsetBounds.minY, "非零原点：纵向沿用按钮")


    // 13. 纠正目标：横向随时可算、纵向要有锁定的顶边才算（这是「先居中再跳」的直接成因）
    //
    //     实测（逐帧轨迹，面板宽 346 / 状态项右边缘 1129）：popover 自己摆在 x=955，
    //     而右对齐目标是 783。原先横向纠正也被「等出场动画结束」挡着，前 240ms 用户看到居中位置。
    let unlocked = PanelAnchor.pinTarget(panelFrame: CGRect(x: 955, y: 524, width: 346, height: 425),
                                         statusItemMaxX: 1129,
                                         lockedTopEdge: nil,
                                         visible: visible)
    assertEqual(unlocked.x, 783, "未锁顶边：横向照样算出右对齐目标 1129 − 346")
    assertEqual(unlocked.y, nil, "未锁顶边：纵向不给目标（调用方保持当前 y）")

    let locked = PanelAnchor.pinTarget(panelFrame: CGRect(x: 955, y: 524, width: 346, height: 425),
                                       statusItemMaxX: 1129,
                                       lockedTopEdge: 949,
                                       visible: visible)
    assertEqual(locked.x, 783, "已锁顶边：横向目标不变")
    assertEqual(locked.y, 524, "已锁顶边：原点 y = 949 − 425")

    // 14. 同一顶边下切不同高度的页：右上角恒定（x 一致、x+高度的一致由第 9~11 条保证）
    var corners: [CGFloat] = []
    for height in [345, 425, 506, 546] as [CGFloat] {
        let target = PanelAnchor.pinTarget(panelFrame: CGRect(x: 955, y: 300, width: 346, height: height),
                                           statusItemMaxX: 1129,
                                           lockedTopEdge: 949,
                                           visible: visible)
        assertEqual(target.x, 783, "高度 " + String(describing: height) + "：横向目标恒定")
        corners.append(target.x + 346)
    }
    assertEqual(Set(corners).count, 1, "高度 345…546 变化时右边缘恒定（实际 " + String(describing: corners) + "）")

    print("✅ PanelAnchor works")
}