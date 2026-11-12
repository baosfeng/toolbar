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

    /// 某个视图点命中的项（nil = 没点在任何按钮上）
    func item(at point: CGPoint) -> SnipBarItem? {
        itemRects.first { $0.rect.contains(point) }?.item
    }

    /// 悬停项编号（-1 表示无），供绘制取气泡文案
    func hoveredItem() -> SnipBarItem? {
        guard itemRects.indices.contains(hoveredIndex) else { return nil }
        return itemRects[hoveredIndex].item
    }

    // MARK: - 悬停跟踪

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        // 只要鼠标移动事件：工具条不抢覆盖层的窗口探测，鼠标移出去时清掉气泡
        let area = NSTrackingArea(rect: bounds,
                                  options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        hoverTracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let index = itemRects.firstIndex { $0.rect.contains(point) } ?? -1
        hoveredIndex = index
    }

    override func mouseExited(with event: NSEvent) {
        hoveredIndex = -1
    }
}
#if DEBUG
/// 仅 DEBUG 取证入口：按栏目取按钮矩形、程序化摆出悬停态
extension SnipToolBarView {

    /// 某个项的矩形（已换算到工具条自身坐标；调用方再按需要在覆盖层里定位）
    func debugRect(_ item: SnipBarItem) -> CGRect {
        itemRects.first { $0.item == item }?.rect ?? .zero
    }

    /// 程序化摆出某个项的悬停态（离屏渲染取证用）
    func debugHover(_ item: SnipBarItem) {
        hoveredIndex = itemRects.firstIndex { $0.item == item } ?? -1
        needsDisplay = true
    }

}
#endif
