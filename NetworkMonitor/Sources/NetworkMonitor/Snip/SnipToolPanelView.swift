import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 二级面板内容

/// 工具条「更多」按钮弹出的二级面板内容
///
/// 一级工具条只留高频项（4 个工具 + 当前色 + 当前线宽 + 4 个动作按钮），
/// 其余工具与全部颜色 / 线宽档位收进这里的二级面板。
/// 面板与工具条共用同一份 SnipToolBarLayout.panelPlan，尺寸与按钮位置不会各算一遍。
enum SnipPanelContent: Equatable {
    /// 收进二级面板的工具
    case tools([SnipTool])
    /// 可选颜色
    case colors([SnipAnnotationColor])
    /// 可选线宽
    case widths([CGFloat])

    var itemCount: Int {
        switch self {
        case .tools(let items): return items.count
        case .colors(let items): return items.count
        case .widths(let items): return items.count
        }
    }

    /// 每行列数：工具 3 列、颜色 4 列、线宽 3 列
    var columns: Int {
        switch self {
        case .tools: return 3
        case .colors: return 4
        case .widths: return 3
        }
    }

    /// 单个按钮宽
    var itemWidth: CGFloat {
        switch self {
        case .tools: return 34
        case .colors: return 30
        case .widths: return 40
        }
    }

    /// 面板整体尺寸
    var size: CGSize {
        SnipToolBarLayout.panelPlan(itemCount: itemCount,
                                    itemWidth: itemWidth,
                                    columns: columns).size
    }

    /// 无障碍名称（面板可被读屏识别，而不是一块无名的自绘黑块）
    var accessibilityLabel: String {
        switch self {
        case .tools: return "标注工具"
        case .colors: return "标注颜色"
        case .widths: return "标注线宽"
        }
    }
}

// MARK: - 二级面板视图

/// 工具条「更多」按钮弹出的自绘面板（工具 / 颜色 / 线宽）
///
/// 自绘而不是放 NSPopover：覆盖层跑在 screenSaver 层级，原生 popover 会被压在下面，
/// 且原生控件在覆盖层里会抢走键盘焦点（截图态下按键要留在覆盖层）。
@MainActor
final class SnipToolPanelView: NSView {

    /// 当前内容
    let content: SnipPanelContent
    /// 已选中项的序号（-1 或越界 = 无选中）
    private let selectedIndex: Int
    /// 选中回写
    var onPick: ((Int) -> Void)?

    private var itemRects: [CGRect] = []

    init(content: SnipPanelContent, selectedIndex: Int?) {
        self.content = content
        self.selectedIndex = selectedIndex ?? -1
        super.init(frame: NSRect(origin: .zero, size: content.size))
        wantsLayer = true
        setAccessibilityRole(.group)
        setAccessibilityLabel(content.accessibilityLabel)
        itemRects = SnipToolBarLayout.panelPlan(itemCount: content.itemCount,
                                                itemWidth: content.itemWidth,
                                                columns: content.columns).itemRects
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
            if isSelected {
                NSColor.white.withAlphaComponent(0.22).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
            }
            switch content {
            case .tools(let tools) where tools.indices.contains(index):
                SnipBarDrawing.drawTool(tools[index], in: rect, alpha: isSelected ? 1 : 0.72)
            case .colors(let colors) where colors.indices.contains(index):
                SnipBarDrawing.drawColorDot(colors[index], in: rect, isSelected: isSelected)
            case .widths(let widths) where widths.indices.contains(index):
                SnipBarDrawing.drawWidth(widths[index], in: rect, isSelected: isSelected)
            default:
                break
            }
        }
    }

    // MARK: - 交互

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        for (index, rect) in itemRects.enumerated() where rect.contains(point) {
            onPick?(index)
            return
        }
    }
}
