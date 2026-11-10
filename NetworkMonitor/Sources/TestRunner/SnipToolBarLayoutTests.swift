import CoreGraphics
import Foundation
import NetworkMonitorUI

// MARK: - 截图工具条布局（回归：右侧比左侧多 17pt 空白）

func runSnipToolBarLayoutTests() {
    print("🧪 Testing snip toolbar layout...")

    let plan = SnipToolBarLayout.plan(toolCount: 10, colorCount: 7, widthCount: 3, actionCount: 4)

    // 左内边距 = 左边界到第一个按钮的距离，右内边距 = 最后一个按钮右边界到整条工具条右边界
    let firstX = plan.toolRects.first?.minX ?? -1
    let lastActionMaxX = plan.actionRects.last?.maxX ?? -1
    assertEqual(firstX, SnipToolBarLayout.padding, "左侧内边距等于 padding")
    assertEqual(plan.width - lastActionMaxX, SnipToolBarLayout.padding, "右侧内边距等于 padding（早期实现这里多出 17pt）")
    assertEqual(plan.width - lastActionMaxX, firstX, "左右内边距恒等")

    // 组数与分隔线：四组之间三条线，画在相邻两组间隙中央
    assertEqual(plan.dividerXs.count, 3, "四组之间三条分隔线")
    assertEqual(plan.dividerXs, plan.dividerXs.sorted(), "分隔线 x 单调递增")

    // 各组的 x 严格递增且互不重叠（组间带必须真的留出空隙）
    let toolMax = plan.toolRects.last?.maxX ?? 0
    let colorMin = plan.colorRects.first?.minX ?? 0
    let colorMax = plan.colorRects.last?.maxX ?? 0
    let widthMin = plan.widthRects.first?.minX ?? 0
    let widthMax = plan.widthRects.last?.maxX ?? 0
    let actionMin = plan.actionRects.first?.minX ?? 0
    assertEqual(colorMin - toolMax, SnipToolBarLayout.groupGap, "工具组与颜色组之间留出组间带")
    assertEqual(widthMin - colorMax, SnipToolBarLayout.groupGap, "颜色组与线宽组之间留出组间带")
    assertEqual(actionMin - widthMax, SnipToolBarLayout.groupGap, "线宽组与动作组之间留出组间带")
    assertEqual(plan.dividerXs[0], toolMax + SnipToolBarLayout.groupGap / 2, "第一条分隔线居中")
    assertEqual(plan.dividerXs[2], widthMax + SnipToolBarLayout.groupGap / 2, "第三条分隔线居中")

    // 按钮尺寸：工具 30、颜色 20、线宽 24、动作 56 × 26
    assertEqual(plan.toolRects.first?.width, SnipToolBarLayout.toolSide, "工具按钮边长")
    assertEqual(plan.colorRects.first?.width, SnipToolBarLayout.colorSide, "颜色圆点边长")
    assertEqual(plan.widthRects.first?.width, SnipToolBarLayout.widthSide, "线宽按钮边长")
    assertEqual(plan.actionRects.first?.width, SnipToolBarLayout.actionWidth, "动作按钮宽")
    assertEqual(plan.actionRects.first?.height, SnipToolBarLayout.actionHeight, "动作按钮高")

    // 垂直居中：每类按钮的竖直中线都落在工具条中线
    let midY = SnipToolBarLayout.height / 2
    for rect in plan.toolRects + plan.colorRects + plan.widthRects + plan.actionRects {
        assertEqual(rect.midY, midY, "按钮竖直居中")
    }

    // 退化输入：某一组为空时不发分隔线、不越界
    let colorLess = SnipToolBarLayout.plan(toolCount: 10, colorCount: 0, widthCount: 3, actionCount: 4)
    assertEqual(colorLess.colorRects.count, 0, "颜色组为空时无按钮")
    assertEqual(colorLess.dividerXs.count, 2, "空组两侧不发分隔线")
    assertEqual(colorLess.width - (colorLess.actionRects.last?.maxX ?? 0), SnipToolBarLayout.padding,
                "空组时右侧内边距仍等于 padding")

    // 数量与真实枚举一致（按钮数与布局计划同源）
    assertEqual(plan.toolRects.count, 10, "10 个标注工具")
    assertEqual(plan.colorRects.count, 7, "7 个颜色")
    assertEqual(plan.widthRects.count, 3, "3 档线宽")
    assertEqual(plan.actionRects.count, 4, "4 个动作按钮")

    print("✅ 截图工具条布局测试通过")
}
