import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 二级面板视图

/// 工具条「更多 / 当前色 / 当前线宽」弹出的自绘面板
///
/// 自绘而不是放 NSPopover：覆盖层跑在 screenSaver 层级，原生 popover 会被压在下面，
/// 且原生控件在覆盖层里会抢走键盘焦点（截图态下按键要留在覆盖层）。
/// 条目文字有三档（与一级工具条同一份 SnipToolBarLabelMode）：
/// 仅图标 / 悬停气泡（默认）/ 图标下方常驻标签。
/// 条目绘制在 `SnipToolPanelView+Drawing.swift`（守住单文件体积门禁）。
@MainActor
final class SnipToolPanelView: NSView {

    /// 当前内容
    let content: SnipPanelContent
    /// 文字提示档（由覆盖层按偏好传入，与一级工具条同源）
    let labelMode: SnipToolBarLabelMode
    /// 已选中项的序号（-1 或越界 = 无选中）
    /// 放宽为 internal：绘制扩展文件要读
    let selectedIndex: Int
    /// 选中回写
    var onPick: ((Int) -> Void)?

    /// 每个条目的矩形
    /// 放宽为 internal：绘制扩展文件要读
    var itemRects: [CGRect] = []
    /// 当前悬停项（-1 = 无）
    /// 放宽为 internal：绘制扩展文件要读
    var hoveredIndex = -1 {
        didSet { if hoveredIndex != oldValue { needsDisplay = true } }
    }
    private var hoverTracking: NSTrackingArea?

    init(content: SnipPanelContent,
         selectedIndex: Int?,
         labelMode: SnipToolBarLabelMode = .hover) {
        self.content = content
        self.labelMode = labelMode
        self.selectedIndex = selectedIndex ?? -1
        super.init(frame: NSRect(origin: .zero, size: content.size(labelMode: labelMode)))
        wantsLayer = true
        setAccessibilityRole(.group)
        setAccessibilityLabel(content.accessibilityLabel)
        itemRects = SnipToolBarLayout.panelPlan(itemCount: content.itemCount,
                                                itemWidth: content.itemWidth,
                                                columns: content.columns,
                                                rowHeight: content.rowHeight(labelMode: labelMode)).itemRects
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("不支持从 nib 创建")
    }

    override var isFlipped: Bool { true }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.82).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()

        for (index, rect) in itemRects.enumerated() {
            let isSelected = index == selectedIndex
            let isHovered = index == hoveredIndex && labelMode.showsHoverBubble
            // 二级面板用另一套选中语言：浅底不变 + 强调色描边，与一级工具条的整格反白区分开
            SnipBarDrawing.drawSelection(isSelected: isSelected, isHovered: isHovered,
                                         in: rect,
                                         style: SnipBarTone.selectionStyle(forPanel: true))
            drawItem(at: index, in: rect, isSelected: isSelected,
                     alpha: SnipBarTone.iconAlpha(isSelected: isSelected, isHovered: isHovered))
            if labelMode.showsPersistentLabel {
                drawPersistentLabel(at: index, in: rect)
            }
        }
        if labelMode.showsHoverBubble, itemRects.indices.contains(hoveredIndex) {
            drawBubble(at: hoveredIndex, over: itemRects[hoveredIndex])
        }
    }

    // MARK: - 交互

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        hoverTracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        hoveredIndex = itemRects.firstIndex { $0.contains(point) } ?? -1
    }

    override func mouseExited(with event: NSEvent) {
        hoveredIndex = -1
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        for (index, rect) in itemRects.enumerated() where rect.contains(point) {
            onPick?(index)
            return
        }
    }
}