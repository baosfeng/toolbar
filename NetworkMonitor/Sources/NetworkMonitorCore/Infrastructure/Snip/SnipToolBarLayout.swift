import CoreGraphics
import Foundation

// MARK: - 截图工具条布局（纯逻辑，可单测）

/// 截图覆盖层底部工具条的排布计划 —— 宽度与按钮位置同源，不可能各算一套
///
/// 背景：早期实现里 `preferredWidth`（整条宽度）与逐一摆放按钮各写一遍累加式，
/// 前者多算了一段组间宽度、后者末尾多算了一个组内间隙，于是整条工具条
/// 右侧多出 17pt 空白而左侧只有 8pt，观感像按钮被挤向左边、右边缘发虚。
/// 这里把两件事收进同一个 plan：左内边距与右内边距必然相等。
///
/// 组顺序、组显隐、按钮尺寸都来自 `SnipToolBarConfiguration` 与 `Metrics`：
/// 设置页改完配置，同一份 plan 立刻按新顺序出宽度，不会出现「条宽按老顺序算、
/// 按钮按新顺序摆」的错位。
public enum SnipToolBarLayout {

    /// 仅图标档的工具条可视高度
    public static let height: CGFloat = 40
    /// 左右内边距（两侧恒等——回归测试直接断言）
    public static let padding: CGFloat = 8
    /// 组间分隔带（分隔线画在带中央）
    public static let groupGap: CGFloat = 16
    /// 工具按钮边长（仅图标档）
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
    /// 悬停气泡占用的上方高度（气泡画在这里，不占工具条可视区）
    public static let bubbleSpace: CGFloat = 28
    /// 气泡自身高度
    public static let bubbleHeight: CGFloat = 24

    /// 一次布局的全部结果
    public struct Plan: Equatable, Sendable {
        /// 整条工具条宽度
        public let width: CGFloat
        /// 工具条可视高度（不含悬停气泡区）
        public let height: CGFloat
        /// 组间分隔线的 x（相邻两组间隙的中央）
        public let dividerXs: [CGFloat]
        public let toolRects: [CGRect]
        public let colorRects: [CGRect]
        public let widthRects: [CGRect]
        public let actionRects: [CGRect]
        /// 按组给出的按钮矩形（被隐藏的组为空数组），供视图按组顺序绘制与命中
        public let groupRects: [SnipToolBarGroup: [CGRect]]
        /// 实际显示出来的组，顺序即排列顺序
        public let orderedGroups: [SnipToolBarGroup]
    }

    /// 一组按钮的排布参数
    public struct Group: Equatable, Sendable {
        public let count: Int
        public let width: CGFloat
        public let gap: CGFloat

        public init(count: Int, width: CGFloat, gap: CGFloat) {
            self.count = count
            self.width = width
            self.gap = gap
        }

        /// 该组自身占用的宽度（不含组间带）
        var span: CGFloat {
            guard count > 0 else { return 0 }
            return CGFloat(count) * width + CGFloat(count - 1) * gap
        }
    }

    /// 尺寸口径 —— 文字提示档决定按钮与整条高度
    public struct Metrics: Equatable, Sendable {
        /// 工具条可视高度
        public let height: CGFloat
        public let tool: CGSize
        public let color: CGSize
        public let width: CGSize
        public let action: CGSize

        public init(height: CGFloat, tool: CGSize, color: CGSize, width: CGSize, action: CGSize) {
            self.height = height
            self.tool = tool
            self.color = color
            self.width = width
            self.action = action
        }
    }

    /// 仅图标档的尺寸（既有常量的一份组合，回归测试与老外观同源）
    public static let compactMetrics = Metrics(
        height: height,
        tool: CGSize(width: toolSide, height: toolSide),
        color: CGSize(width: colorSide, height: colorSide),
        width: CGSize(width: widthSide, height: widthSide),
        action: CGSize(width: actionWidth, height: actionHeight))

    /// 常驻标签档的尺寸：按钮加宽、整条加高，给 9.5pt 标签留出位置
    public static let labeledMetrics = Metrics(
        height: 50,
        tool: CGSize(width: 46, height: 42),
        color: CGSize(width: 40, height: 42),
        width: CGSize(width: 40, height: 42),
        action: CGSize(width: actionWidth, height: actionHeight))

    /// 按文字提示档取尺寸：仅图标 / 悬停都是 40pt 条高，常驻标签才是 50pt
    public static func metrics(for mode: SnipToolBarLabelMode) -> Metrics {
        mode.showsPersistentLabel ? labeledMetrics : compactMetrics
    }

    /// 该档下工具条的可视高度
    public static func barHeight(for mode: SnipToolBarLabelMode) -> CGFloat {
        metrics(for: mode).height
    }

    /// 该档下工具条视图的完整高度（悬停档要把气泡空间算进去）
    public static func outerHeight(for mode: SnipToolBarLabelMode) -> CGFloat {
        metrics(for: mode).height + (mode.showsHoverBubble ? bubbleSpace : 0)
    }

    /// 按一份配置计算整条工具条的排布
    public static func plan(config: SnipToolBarConfiguration) -> Plan {
        let counts: [SnipToolBarGroup: Int] = [
            .tools: config.toolGroupCount,
            .color: config.colorGroupCount,
            .width: config.widthGroupCount,
            .actions: config.actionGroupCount,
        ]
        return plan(counts: counts, order: config.groupOrder, metrics: metrics(for: config.labelMode))
    }

    /// 按「组 → 按钮数」与组顺序计算排布（空组既不占宽也不发分隔线）
    public static func plan(counts: [SnipToolBarGroup: Int],
                            order: [SnipToolBarGroup],
                            metrics: Metrics) -> Plan {
        func group(for kind: SnipToolBarGroup) -> Group {
            let count = max(counts[kind] ?? 0, 0)
            switch kind {
            case .tools: return Group(count: count, width: metrics.tool.width, gap: toolGap)
            case .color: return Group(count: count, width: metrics.color.width, gap: colorGap)
            case .width: return Group(count: count, width: metrics.width.width, gap: widthGap)
            case .actions: return Group(count: count, width: metrics.action.width, gap: actionGap)
            }
        }

        // 组顺序去重并补全：调用方传进来的顺序可能缺项或被手工改坏
        let normalizedOrder = SnipToolBarGroup.order(from: order.map(\.rawValue))
        let groups = normalizedOrder.map { (kind: $0, value: group(for: $0)) }
        let visible = groups.filter { $0.value.count > 0 }
        let gapCount = CGFloat(max(visible.count - 1, 0))
        let content = visible.reduce(CGFloat(0)) { $0 + $1.value.span }
        let totalWidth = padding * 2 + content + groupGap * gapCount

        var groupRects: [SnipToolBarGroup: [CGRect]] = [:]
        var dividerXs: [CGFloat] = []
        var cursor = padding
        for (index, entry) in visible.enumerated() {
            groupRects[entry.kind] = cells(count: entry.value.count,
                                           cellSize: cellSize(for: entry.kind, metrics: metrics),
                                           gap: entry.value.gap,
                                           startX: cursor,
                                           midY: metrics.height / 2)
            let end = cursor + entry.value.span
            cursor = end
            if index < visible.count - 1 {
                dividerXs.append(end + groupGap / 2)
                cursor += groupGap
            }
        }

        return Plan(width: totalWidth,
                    height: metrics.height,
                    dividerXs: dividerXs,
                    toolRects: groupRects[.tools] ?? [],
                    colorRects: groupRects[.color] ?? [],
                    widthRects: groupRects[.width] ?? [],
                    actionRects: groupRects[.actions] ?? [],
                    groupRects: groupRects,
                    orderedGroups: visible.map(\.kind))
    }

    /// 计算整条工具条的排布（老签名：固定「工具 → 颜色 → 线宽 → 动作」组序、仅图标档尺寸）
    public static func plan(toolCount: Int,
                            colorCount: Int,
                            widthCount: Int,
                            actionCount: Int) -> Plan {
        plan(counts: [.tools: toolCount, .color: colorCount, .width: widthCount, .actions: actionCount],
             order: [SnipToolBarGroup.tools, .color, .width, .actions],
             metrics: compactMetrics)
    }

    /// 组的单元高度（竖直居中时用）
    private static func cellSize(for kind: SnipToolBarGroup, metrics: Metrics) -> CGSize {
        switch kind {
        case .tools: return metrics.tool
        case .color: return metrics.color
        case .width: return metrics.width
        case .actions: return metrics.action
        }
    }

    // MARK: - 二级面板

    /// 二级面板的排布（工具 / 样式收进弹出层以后，一级工具条只留高频项）
    ///
    /// 面板贴着工具条上沿弹出，内部按网格摆放：宽 = 列数 × 单元 + 间隙，
    /// 高 = 行数 × 行高 + 间隙。列数由调用方按内容给出，纯逻辑保证不会被挤成两行。
    public struct PanelPlan: Equatable, Sendable {
        /// 面板整体尺寸（含内边距）
        public let size: CGSize
        /// 每个按钮的矩形（面板局部坐标，左上原点）
        public let itemRects: [CGRect]
        /// 列数
        public let columns: Int
    }

    /// 面板内边距、行高与间隙
    public static let panelPadding: CGFloat = 8
    public static let panelItemGap: CGFloat = 4
    public static let panelRowHeight: CGFloat = 30
    /// 带文字标签时每个按钮占行高（图标 30 + 标签 14）
    public static let panelLabeledRowHeight: CGFloat = 44

    /// 计算二级面板排布
    ///
    /// - Parameters:
    ///   - itemCount: 按钮数量
    ///   - itemWidth: 单个按钮宽
    ///   - columns: 每行列数（调用方按面板最大宽给出）
    ///   - rowHeight: 每行高度（带标签的面板传 panelLabeledRowHeight）
    public static func panelPlan(itemCount: Int,
                                 itemWidth: CGFloat,
                                 columns: Int,
                                 rowHeight: CGFloat = panelRowHeight) -> PanelPlan {
        guard itemCount > 0, columns > 0, itemWidth > 0, rowHeight > 0 else {
            return PanelPlan(size: .zero, itemRects: [], columns: max(columns, 0))
        }
        let usedColumns = min(columns, itemCount)
        let rows = Int(ceil(Double(itemCount) / Double(usedColumns)))
        let contentWidth = CGFloat(usedColumns) * itemWidth + CGFloat(usedColumns - 1) * panelItemGap
        let contentHeight = CGFloat(rows) * rowHeight + CGFloat(rows - 1) * panelItemGap
        let size = CGSize(width: contentWidth + panelPadding * 2,
                          height: contentHeight + panelPadding * 2)
        var rects: [CGRect] = []
        rects.reserveCapacity(itemCount)
        for index in 0..<itemCount {
            let row = index / usedColumns
            let column = index % usedColumns
            rects.append(CGRect(x: panelPadding + CGFloat(column) * (itemWidth + panelItemGap),
                                y: panelPadding + CGFloat(row) * (rowHeight + panelItemGap),
                                width: itemWidth,
                                height: rowHeight))
        }
        return PanelPlan(size: size, itemRects: rects, columns: usedColumns)
    }

    /// 把一组按钮按「单元宽 + 组内间隙」摆成一行
    private static func cells(count: Int,
                              cellSize: CGSize,
                              gap: CGFloat,
                              startX: CGFloat,
                              midY: CGFloat) -> [CGRect] {
        guard count > 0 else { return [] }
        let step = cellSize.width + gap
        var rects: [CGRect] = []
        rects.reserveCapacity(count)
        for index in 0..<count {
            let originX = startX + CGFloat(index) * step
            let originY = midY - cellSize.height / 2
            rects.append(CGRect(x: originX, y: originY,
                                width: cellSize.width, height: cellSize.height))
        }
        return rects
    }
}
