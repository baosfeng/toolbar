import CoreGraphics
import Foundation
import NetworkMonitorCore
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

    // MARK: 二级面板排布（工具 / 样式收进弹出层）

    // 10 个工具收进 2 行 5 列：面板比一级工具条更窄，不会横向撑满屏幕
    let toolPanel = SnipToolBarLayout.panelPlan(itemCount: 10, itemWidth: 32, columns: 5)
    assertEqual(toolPanel.columns, 5, "5 列")
    assertEqual(toolPanel.itemRects.count, 10, "10 个按钮都有位置")
    assertEqual(toolPanel.size.width,
                CGFloat(5) * 32 + CGFloat(4) * SnipToolBarLayout.panelItemGap + SnipToolBarLayout.panelPadding * 2,
                "面板宽度 = 列数 × 单元 + 间隙 + 两侧内边距")
    assertEqual(toolPanel.size.height,
                CGFloat(2) * SnipToolBarLayout.panelRowHeight + SnipToolBarLayout.panelItemGap
                    + SnipToolBarLayout.panelPadding * 2,
                "2 行高度的面板")
    // 第一行与第二行的 x 完全对齐，行间距为面板间隙
    let firstRow = Array(toolPanel.itemRects[0..<5])
    let secondRow = Array(toolPanel.itemRects[5..<10])
    assertEqual(secondRow[0].minY - firstRow[0].minY,
                SnipToolBarLayout.panelRowHeight + SnipToolBarLayout.panelItemGap,
                "行间距 = 行高 + 面板间隙")
    for index in 0..<5 {
        assertEqual(secondRow[index].minX, firstRow[index].minX, "两行同列 x 对齐")
    }
    // 所有按钮都落在面板矩形内
    for rect in toolPanel.itemRects {
        assertEqual(rect.maxX <= toolPanel.size.width + 0.01, true, "按钮不越出面板右边界")
        assertEqual(rect.maxY <= toolPanel.size.height + 0.01, true, "按钮不越出面板下边界")
    }

    // 颜色 7 个一列排开（竖条），面板高度随条目数增长
    let colorPanel = SnipToolBarLayout.panelPlan(itemCount: 7, itemWidth: 28, columns: 1)
    assertEqual(colorPanel.columns, 1, "一列")
    assertEqual(colorPanel.size.width,
                CGFloat(28) + SnipToolBarLayout.panelPadding * 2, "单列面板宽度")
    assertEqual(colorPanel.size.height,
                CGFloat(7) * SnipToolBarLayout.panelRowHeight + CGFloat(6) * SnipToolBarLayout.panelItemGap
                    + SnipToolBarLayout.panelPadding * 2, "7 行的面板高度")

    // 退化输入：0 个按钮不产出面板
    let empty = SnipToolBarLayout.panelPlan(itemCount: 0, itemWidth: 32, columns: 5)
    assertEqual(empty.size, .zero, "0 个按钮时面板尺寸为 0")
    assertEqual(empty.itemRects.count, 0, "0 个按钮时无矩形")
    // 列数超过条目数时退化为一行
    let single = SnipToolBarLayout.panelPlan(itemCount: 2, itemWidth: 32, columns: 5)
    assertEqual(single.columns, 2, "列数夹到条目数")
    assertEqual(single.itemRects.count, 2, "两个按钮一行")

    // 一级工具条的真实参数：4 个常驻工具 + 更多 + 当前色 + 当前线宽 + 4 个动作按钮
    // （动作按钮枚举在可执行 target 里，TestRunner 只认数量 4）
    let primary = SnipToolBarLayout.plan(toolCount: SnipTool.primary.count + 1,
                                         colorCount: 1, widthCount: 1,
                                         actionCount: 4)
    assertEqual(primary.toolRects.count, 5, "工具组 5 个位置（4 个工具 + 更多）")
    assertEqual(primary.colorRects.count, 1, "颜色组只放当前色")
    assertEqual(primary.widthRects.count, 1, "线宽组只放当前档")
    assertEqual(primary.actionRects.count, 4, "动作组 4 个按钮")
    assertEqual(primary.width < 540, true, "一级工具条收窄到 540pt 以内（原全摊开 869pt）")
    assertEqual(primary.width > 300, true, "收窄后仍放得下全部高频项")

    // 工具分层：常驻 4 个 + 溢出 6 个 = 全部 10 个，且两者无交集
    assertEqual(SnipTool.primary.count, 4, "一级工具条常驻 4 个工具")
    assertEqual(SnipTool.overflow.count, 6, "二级面板收 6 个工具")
    assertEqual(SnipTool.primary.count + SnipTool.overflow.count, SnipTool.allCases.count, "分层后不丢工具")
    for tool in SnipTool.primary {
        assertEqual(SnipTool.overflow.contains(tool), false, "常驻与溢出工具不重叠")
    }
    assertEqual(SnipTool.primary, [.rectangle, .arrow, .text, .mosaic], "常驻工具是最高频的四个")

    print("✅ 截图工具条布局测试通过")
}
