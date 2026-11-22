import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 工具条排版（按配置逐组摆放）

/// 从主类拆出：主文件守 500 行 / 15 KiB 门禁，排版与绘制分开各管一件事
extension SnipToolBarView {

    /// 按当前配置重算全部矩形（每帧与配置变更时都走这里，只有一份算法）
    func rebuildLayout() {
        let mode = configuration.labelMode
        let metrics = SnipToolBarLayout.metrics(for: mode)
        let plan = SnipToolBarLayout.plan(config: configuration)
        barHeight = metrics.height
        // 悬停档把气泡画在可视条上方，视图比可视条高 bubbleSpace
        barOriginY = mode.showsHoverBubble ? SnipToolBarLayout.bubbleSpace : 0

        var rects: [(item: SnipBarItem, rect: CGRect)] = []
        func shift(_ rect: CGRect) -> CGRect {
            rect.offsetBy(dx: 0, dy: barOriginY)
        }

        for (index, tool) in configuration.primaryTools.enumerated() {
            guard plan.toolRects.indices.contains(index) else { continue }
            rects.append((.tool(tool), shift(plan.toolRects[index])))
        }
        // 工具组末尾是「更多」：没有溢出工具时不发这个入口
        if !configuration.overflowTools.isEmpty,
           plan.toolRects.indices.contains(configuration.primaryTools.count) {
            rects.append((.more, shift(plan.toolRects[configuration.primaryTools.count])))
        }
        if let colorRect = plan.colorRects.first {
            rects.append((.color, shift(colorRect)))
        }
        if let widthRect = plan.widthRects.first {
            rects.append((.width, shift(widthRect)))
        }
        for (index, action) in configuration.visibleActions.enumerated() {
            guard configuration.isVisible(.actions),
                  plan.actionRects.indices.contains(index) else { continue }
            rects.append((.action(action), shift(plan.actionRects[index])))
        }
        // 命中按固定优先级排序：悬浮/点击都取最近的一个，视觉上重叠也不会跳
        itemRects = rects.sorted { $0.rect.minX < $1.rect.minX }
        dividerXs = plan.dividerXs
        hoveredIndex = -1
    }
}
