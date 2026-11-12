import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 二级面板内容

/// 工具条「更多 / 颜色 / 线宽」按钮弹出的二级面板内容
///
/// 一级工具条只留高频项，其余工具与全部颜色 / 线宽档位收进这里的二级面板。
/// 面板与工具条共用同一份 SnipToolBarLayout.panelPlan，尺寸与按钮位置不会各算一遍；
/// 条目文字（工具名 / 颜色名 / 线宽值）由 SnipPanelLabelText 与工具条共用一份口径。
enum SnipPanelContent: Equatable {
    /// 收进二级面板的工具
    case tools([SnipTool])
    /// 可选颜色
    case colors([SnipAnnotationColor])
    /// 可选线宽
    case widths([CGFloat])
    /// 样式面板：线宽 + 实线/虚线 + 颜色透明度
    ///
    /// 官方把三件事放在同一支笔的设置里：线宽、虚线/点线、颜色 Alpha。
    /// 分成三个独立面板会让用户来回点三次，这里合并成一个盘面。
    case styles(widths: [CGFloat], dashes: [Bool], alphas: [CGFloat])

    var itemCount: Int {
        switch self {
        case .tools(let items): return items.count
        case .colors(let items): return items.count
        case .widths(let items): return items.count
        case .styles(let widths, let dashes, let alphas):
            return widths.count + dashes.count + alphas.count
        }
    }

    /// 每行列数：工具 3 列、颜色 4 列、线宽 3 列、样式 4 列
    var columns: Int {
        switch self {
        case .tools: return 3
        case .colors: return 4
        case .widths: return 3
        case .styles: return 4
        }
    }

    /// 单个按钮宽
    var itemWidth: CGFloat {
        switch self {
        case .tools: return 34
        case .colors: return 30
        case .widths: return 40
        case .styles: return 38
        }
    }

    /// 面板整体尺寸（按文字提示档决定行高：常驻标签档行高 44、其余 30）
    func size(labelMode: SnipToolBarLabelMode) -> CGSize {
        SnipToolBarLayout.panelPlan(itemCount: itemCount,
                                    itemWidth: itemWidth,
                                    columns: columns,
                                    rowHeight: rowHeight(labelMode: labelMode)).size
    }

    /// 行高：常驻标签档要给图标下方的文字留位置
    func rowHeight(labelMode: SnipToolBarLabelMode) -> CGFloat {
        labelMode.showsPersistentLabel ? SnipToolBarLayout.panelLabeledRowHeight
            : SnipToolBarLayout.panelRowHeight
    }

    /// 单个条目的名称（悬停气泡与常驻标签共用）
    func itemTitle(at index: Int) -> String {
        switch self {
        case .tools(let tools):
            return tools.indices.contains(index) ? tools[index].displayName : ""
        case .colors(let colors):
            return colors.indices.contains(index)
                ? SnipAnnotationColorNaming.name(for: colors[index]) : ""
        case .widths(let widths):
            return widths.indices.contains(index) ? SnipPanelLabelText.width(widths[index]) : ""
        case .styles(let widths, let dashes, let alphas):
            if widths.indices.contains(index) { return SnipPanelLabelText.width(widths[index]) }
            let offset = index - widths.count
            if dashes.indices.contains(offset) { return SnipPanelLabelText.dash(dashes[offset]) }
            let alphaIndex = offset - dashes.count
            if alphas.indices.contains(alphaIndex) {
                return SnipPanelLabelText.alpha(alphas[alphaIndex])
            }
            return ""
        }
    }

    /// 无障碍名称（面板可被读屏识别，而不是一块无名的自绘黑块）
    var accessibilityLabel: String {
        switch self {
        case .tools: return "标注工具"
        case .colors: return "标注颜色"
        case .widths: return "标注线宽"
        case .styles: return "画笔样式（线宽 / 虚线 / 透明度）"
        }
    }
}

// MARK: - 二级面板视图

/// 工具条「更多 / 当前色 / 当前线宽」弹出的自绘面板
///
/// 自绘而不是放 NSPopover：覆盖层跑在 screenSaver 层级，原生 popover 会被压在下面，
/// 且原生控件在覆盖层里会抢走键盘焦点（截图态下按键要留在覆盖层）。
/// 条目文字有三档（与一级工具条同一份 SnipToolBarLabelMode）：
/// 仅图标 / 悬停气泡（默认）/ 图标下方常驻标签。
@MainActor
final class SnipToolPanelView: NSView {

    /// 当前内容
    let content: SnipPanelContent
    /// 文字提示档（由覆盖层按偏好传入，与一级工具条同源）
    let labelMode: SnipToolBarLabelMode
    /// 已选中项的序号（-1 或越界 = 无选中）
    private let selectedIndex: Int
    /// 选中回写
    var onPick: ((Int) -> Void)?

    private var itemRects: [CGRect] = []
    /// 当前悬停项（-1 = 无）
    private var hoveredIndex = -1 {
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
            if isSelected || isHovered {
                NSColor.white.withAlphaComponent(isSelected ? 0.22 : 0.14).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
            }
            drawItem(at: index, in: rect, isSelected: isSelected,
                     alpha: isSelected ? 1 : (isHovered ? 0.95 : 0.72))
            if labelMode.showsPersistentLabel {
                drawPersistentLabel(at: index, in: rect)
            }
        }
        if labelMode.showsHoverBubble, itemRects.indices.contains(hoveredIndex) {
            drawBubble(at: hoveredIndex, over: itemRects[hoveredIndex])
        }
    }

    /// 单个条目（工具图标 / 颜色圆点 / 线宽条 / 线型样本 / 透明度圆点）
    private func drawItem(at index: Int, in rect: CGRect, isSelected: Bool, alpha: CGFloat) {
        let iconRect = labelMode.showsPersistentLabel
            ? CGRect(x: rect.midX - 11, y: rect.minY + 3, width: 22, height: 22)
            : rect
        switch content {
        case .tools(let tools) where tools.indices.contains(index):
            SnipBarDrawing.drawTool(tools[index], in: iconRect, alpha: alpha,
                                    inset: labelMode.showsPersistentLabel ? 1 : 6)
        case .colors(let colors) where colors.indices.contains(index):
            SnipBarDrawing.drawColorDot(colors[index], in: iconRect, isSelected: isSelected)
        case .widths(let widths) where widths.indices.contains(index):
            SnipBarDrawing.drawWidth(widths[index], in: iconRect, isSelected: isSelected)
        case .styles(let widths, let dashes, let alphas):
            drawStyleItem(widths: widths, dashes: dashes, alphas: alphas,
                          index: index, rect: iconRect, isSelected: isSelected)
        default:
            break
        }
    }

    /// 样式面板的单项：线宽 → 粗细条、虚线 → 虚线段、透明度 → 半透明圆点
    private func drawStyleItem(widths: [CGFloat],
                               dashes: [Bool],
                               alphas: [CGFloat],
                               index: Int,
                               rect: CGRect,
                               isSelected: Bool) {
        if widths.indices.contains(index) {
            SnipBarDrawing.drawWidth(widths[index], in: rect, isSelected: isSelected)
            return
        }
        let offset = index - widths.count
        if dashes.indices.contains(offset) {
            SnipBarDrawing.drawDashSample(dashed: dashes[offset], in: rect, isSelected: isSelected)
            return
        }
        let alphaIndex = offset - dashes.count
        if alphas.indices.contains(alphaIndex) {
            SnipBarDrawing.drawAlphaDot(alpha: alphas[alphaIndex], in: rect, isSelected: isSelected)
        }
    }

    /// 常驻标签：图标下方 9.5pt 名称
    private func drawPersistentLabel(at index: Int, in rect: CGRect) {
        let text = content.itemTitle(at: index)
        guard !text.isEmpty else { return }
        var attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9.5, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.62),
        ]
        let string = text as NSString
        var size = string.size(withAttributes: attributes)
        if size.width > rect.width {
            let factor = max(rect.width / max(size.width, 1), 0.6)
            attributes[.font] = NSFont.systemFont(ofSize: 9.5 * factor, weight: .regular)
            size = string.size(withAttributes: attributes)
        }
        string.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.maxY - size.height - 1),
                    withAttributes: attributes)
    }

    /// 悬停气泡：贴在被悬停条目上方（放不下就压到条目下方）
    private func drawBubble(at index: Int, over rect: CGRect) {
        let text = content.itemTitle(at: index)
        guard !text.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11.5, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let string = text as NSString
        let size = string.size(withAttributes: attributes)
        let padding = NSSize(width: 8, height: 4)
        let bubbleSize = CGSize(width: size.width + padding.width * 2,
                                height: size.height + padding.height * 2)
        var originX = rect.midX - bubbleSize.width / 2
        originX = min(max(originX, 2), max(bounds.width - bubbleSize.width - 2, 2))
        var originY = rect.minY - bubbleSize.height - 4
        if originY < 2 {
            originY = min(rect.maxY + 4, max(bounds.height - bubbleSize.height - 2, 2))
        }
        let bubbleRect = CGRect(origin: CGPoint(x: originX, y: originY), size: bubbleSize)
        NSColor.black.withAlphaComponent(0.92).setFill()
        let path = NSBezierPath(roundedRect: bubbleRect, xRadius: 6, yRadius: 6)
        path.fill()
        NSColor.white.withAlphaComponent(0.16).setStroke()
        path.lineWidth = 1
        path.stroke()
        string.draw(at: CGPoint(x: bubbleRect.minX + padding.width,
                                y: bubbleRect.minY + padding.height),
                    withAttributes: attributes)
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

    #if DEBUG
    /// 仅 DEBUG：程序化摆出悬停态（离屏取证用）
    func debugHover(index: Int) {
        hoveredIndex = itemRects.indices.contains(index) ? index : -1
        needsDisplay = true
    }
    #endif
}
