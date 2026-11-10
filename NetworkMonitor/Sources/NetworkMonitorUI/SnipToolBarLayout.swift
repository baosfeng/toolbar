import CoreGraphics
import Foundation

// MARK: - 截图工具条布局（纯逻辑，可单测）

/// 截图覆盖层底部工具条的排布计划 —— 宽度与按钮位置同源，不可能各算一套
///
/// 背景：早期实现里 `preferredWidth`（整条宽度）与逐一摆放按钮各写一遍累加式，
/// 前者多算了一段组间宽度、后者末尾多算了一个组内间隙，于是整条工具条
/// 右侧多出 17pt 空白而左侧只有 8pt，观感像按钮被挤向左边、右边缘发虚。
/// 这里把两件事收进同一个 plan：左内边距与右内边距必然相等。
public enum SnipToolBarLayout {

    /// 工具条高度
    public static let height: CGFloat = 40
    /// 左右内边距（两侧恒等——回归测试直接断言）
    public static let padding: CGFloat = 8
    /// 组间分隔带（分隔线画在带中央）
    public static let groupGap: CGFloat = 16
    /// 工具按钮边长
    public static let toolSide: CGFloat = 30
    public static let toolGap: CGFloat = 3
    /// 颜色圆点边长
    public static let colorSide: CGFloat = 20
    public static let colorGap: CGFloat = 3
    /// 线宽按钮边长
    public static let widthSide: CGFloat = 24
    public static let widthGap: CGFloat = 3
    /// 动作按钮尺寸
    public static let actionWidth: CGFloat = 56
    public static let actionHeight: CGFloat = 26
    public static let actionGap: CGFloat = 6

    /// 一次布局的全部结果
    public struct Plan: Equatable {
        /// 整条工具条宽度
        public let width: CGFloat
        /// 三条组间分隔线的 x（相邻两组间隙的中央）
        public let dividerXs: [CGFloat]
        public let toolRects: [CGRect]
        public let colorRects: [CGRect]
        public let widthRects: [CGRect]
        public let actionRects: [CGRect]
    }

    /// 一组按钮的排布参数
    public struct Group {
        public let count: Int
        public let width: CGFloat
        public let gap: CGFloat

        /// 该组自身占用的宽度（不含组间带）
        var span: CGFloat {
            guard count > 0 else { return 0 }
            return CGFloat(count) * width + CGFloat(count - 1) * gap
        }
    }

    /// 一组按钮与其起始 x
    public struct Placement {
        public let group: Group
        public let cellHeight: CGFloat
        public let startX: CGFloat
    }

    /// 计算整条工具条的排布
    public static func plan(toolCount: Int,
                            colorCount: Int,
                            widthCount: Int,
                            actionCount: Int) -> Plan {
        let groups = [
            Group(count: toolCount, width: toolSide, gap: toolGap),
            Group(count: colorCount, width: colorSide, gap: colorGap),
            Group(count: widthCount, width: widthSide, gap: widthGap),
            Group(count: actionCount, width: actionWidth, gap: actionGap)
        ]
        let heights: [CGFloat] = [toolSide, colorSide, widthSide, actionHeight]

        // 空组不占位：既不占宽，也不为它多发一条组间带。
        // 需要消除的组（例如「只剩动作按钮」的极简模式）才不会在左侧留一段空气。
        let visible = (0..<groups.count).filter { groups[$0].count > 0 }
        let gapCount = CGFloat(max(visible.count - 1, 0))
        let content = visible.reduce(CGFloat(0)) { $0 + groups[$1].span }
        let totalWidth = padding * 2 + content + groupGap * gapCount

        var placements: [Int: Placement] = [:]
        var dividerXs: [CGFloat] = []
        var cursor = padding
        for (order, index) in visible.enumerated() {
            placements[index] = Placement(group: groups[index],
                                          cellHeight: heights[index],
                                          startX: cursor)
            let end = cursor + groups[index].span
            cursor = end
            if order < visible.count - 1 {
                dividerXs.append(end + groupGap / 2)
                cursor += groupGap
            }
        }

        func rects(_ index: Int) -> [CGRect] {
            guard let placement = placements[index] else { return [] }
            return cells(in: placement)
        }

        return Plan(width: totalWidth,
                    dividerXs: dividerXs,
                    toolRects: rects(0),
                    colorRects: rects(1),
                    widthRects: rects(2),
                    actionRects: rects(3))
    }

    /// 把一组按钮按「单元宽 + 组内间隙」摆成一行
    private static func cells(in placement: Placement) -> [CGRect] {
        let group = placement.group
        guard group.count > 0 else { return [] }
        let centerY = height / 2
        let step = group.width + group.gap
        var rects: [CGRect] = []
        rects.reserveCapacity(group.count)
        for index in 0..<group.count {
            let originX = placement.startX + CGFloat(index) * step
            let originY = centerY - placement.cellHeight / 2
            rects.append(CGRect(x: originX, y: originY,
                                width: group.width, height: placement.cellHeight))
        }
        return rects
    }
}
