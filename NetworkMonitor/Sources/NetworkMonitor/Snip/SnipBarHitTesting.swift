import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 工具条命中 / 可用性 / 悬停跟踪

/// 排版只管「按钮摆在哪」，这里只管「鼠标点到了谁、这会儿点不点得动」：
/// 置灰项统一按「没点中」处理，于是点击派发与悬停提亮共用同一条判据。
extension SnipToolBarView {

    /// 某个视图点命中的项（nil = 没点在任何按钮上，或命中的是置灰项）
    ///
    /// 置灰项直接按「没点中」处理：命中判定与点击派发共用这一处，
    /// 于是「不响应点击」只需要在判据里写一次，不会出现「悬停仍提亮、点了却没反应」。
    func item(at point: CGPoint) -> SnipBarItem? {
        guard let hit = itemRects.first(where: { $0.rect.contains(point) })?.item,
              isEnabled(hit) else { return nil }
        return hit
    }

    /// 该项此刻能不能点（只有撤销 / 重做会随标注栈变化）
    func isEnabled(_ item: SnipBarItem) -> Bool {
        guard case .action(let action) = item else { return true }
        return annotationAvailability.isEnabled(action)
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
        // 置灰项不参与悬停：气泡与提亮都在暗示「这里可以点」
        let index = itemRects.firstIndex { $0.rect.contains(point) && isEnabled($0.item) } ?? -1
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
    ///
    /// 与真实鼠标走同一判据：置灰项不接受悬停，否则取证图上会出现
    /// 「不可用的按钮还弹着气泡」，反过来误导人以为它可点。
    func debugHover(_ item: SnipBarItem) {
        hoveredIndex = isEnabled(item)
            ? itemRects.firstIndex { $0.item == item } ?? -1
            : -1
        needsDisplay = true
    }

}
#endif