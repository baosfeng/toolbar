import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 工具条回调

/// 一级工具条上的可点项 —— 命中判定与绘制共用同一份列表，不会各算一套
enum SnipBarItem: Equatable {
    case tool(SnipTool)
    /// 「更多」入口（收进二级面板的工具）
    case more
    case color
    case width
    case action(SnipBarAction)
}

@MainActor
protocol SnipToolBarViewDelegate: AnyObject {
    /// 切换工具；nil 表示回到「选区操作」模式
    func toolBarDidChangeTool(_ tool: SnipTool?)
    /// 切换颜色或线宽
    func toolBarDidChangeStyle(_ style: SnipAnnotationStyle)
    /// 点击右侧动作按钮（取消 / 复制 / 保存 / 贴图）
    func toolBarDidPerform(_ action: SnipBarAction)
    /// 请求在工具条上方弹出二级面板（工具 / 颜色 / 线宽）
    /// - Parameters:
    ///   - content: 面板内容
    ///   - anchor: 触发按钮在覆盖层坐标里的矩形（面板据此定位）
    func toolBarDidRequestPanel(_ content: SnipPanelContent, anchor: CGRect)
}

// MARK: - 标注工具条

/// 选区下方的标注工具条 — 自绘按钮，避免在浮动覆盖层里放原生控件
///
/// 排版完全由 `SnipToolBarConfiguration` 驱动：组顺序、组显隐、常驻工具、动作按钮
/// 都在设置页可改，视图不再写死「工具 → 颜色 → 线宽 → 动作」这一套顺序。
/// 文字描述有三档（`SnipToolBarLabelMode`）：仅图标 / 悬停气泡（默认，对齐 Snipaste）/
/// 常驻标签。悬停气泡画在按钮上方留出的 28pt 空间里，不压住选区内容。
@MainActor
final class SnipToolBarView: NSView {

    weak var delegate: SnipToolBarViewDelegate?

    /// 当前生效配置（设置页写入偏好后由覆盖层灌进来）
    /// 放宽为 internal：绘制与命中扩展文件要读
    var configuration: SnipToolBarConfiguration = .standard {
        didSet {
            guard configuration != oldValue else { return }
            rebuildLayout()
            needsDisplay = true
        }
    }

    /// 当前工具；属于二级面板里的工具时，「更多」按钮显示该工具图标并高亮
    /// 放宽为 internal：DEBUG 取证要在离屏渲染里摆出「已选中」状态
    var selectedTool: SnipTool? {
        didSet { needsDisplay = true }
    }

    private(set) var style = SnipAnnotationStyle() {
        didSet { needsDisplay = true }
    }

    /// 由覆盖层回灌样式（二级面板里选了颜色 / 线宽后一级工具条要跟着变）
    func updateStyle(_ newStyle: SnipAnnotationStyle) {
        style = newStyle
    }

    /// 仅 DEBUG：离屏取证时设置已选中的颜色 / 线宽
    #if DEBUG
    func debugSetStyle(_ newStyle: SnipAnnotationStyle) {
        style = newStyle
        needsDisplay = true
    }
    #endif

    /// 工具条上可选的颜色与线宽（二级面板的内容与工具条当前值的来源，只此一份）
    static let colors: [SnipAnnotationColor] = [.red, .orange, .yellow, .green, .blue, .black, .white]
    /// 线宽档（与 SnipLineWidthStepper.widths 同源，两者共用一份，不再各写一份）
    static let widths: [CGFloat] = SnipLineWidthStepper.widths
    /// 实线 / 虚线两档
    static let dashes: [Bool] = [false, true]
    /// 颜色透明度三档：不透明 / 半透明 / 淡
    static let alphas: [CGFloat] = [1.0, 0.6, 0.3]

    // MARK: 布局结果（每次重算，bounds 变化后仍然对齐）

    /// 每个可点项的矩形（视图局部坐标，已含顶部气泡区偏移）
    /// 放宽为 internal：绘制与命中扩展文件要读
    var itemRects: [(item: SnipBarItem, rect: CGRect)] = []
    /// 组间分隔线的 x（与按钮排布同源，避免两处各算一遍）
    var dividerXs: [CGFloat] = []
    /// 可视条相对视图顶部的 y 偏移（悬停档要给它上方的气泡让出空间）
    var barOriginY: CGFloat = 0
    /// 可视条高度（不含气泡区）
    var barHeight: CGFloat = SnipToolBarLayout.height
    /// 当前悬停项（-1 = 无），决定气泡与提亮
    var hoveredIndex = -1 { didSet { if hoveredIndex != oldValue { needsDisplay = true } } }
    /// 二级面板是否展开（展开时不画气泡，否则气泡会露在面板底下）
    var isPanelOpen = false { didSet { if isPanelOpen != oldValue { needsDisplay = true } } }
    /// 放宽为 internal：悬停跟踪在排版扩展文件里安装与移除
    var hoverTracking: NSTrackingArea?

    override var isFlipped: Bool { true }

    init(configuration: SnipToolBarConfiguration = .standard) {
        self.configuration = configuration
        super.init(frame: Self.frameSize(for: configuration))
        wantsLayer = true
        setAccessibilityRole(.group)
        setAccessibilityLabel("截图标注工具条")
        rebuildLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("不支持从 nib 创建")
    }

    /// 一份配置对应的视图尺寸（宽 = 排布宽度，高 = 条高 + 气泡区）
    static func frameSize(for configuration: SnipToolBarConfiguration) -> CGRect {
        let plan = SnipToolBarLayout.plan(config: configuration)
        let outer = SnipToolBarLayout.outerHeight(for: configuration.labelMode)
        return CGRect(x: 0, y: 0, width: plan.width, height: outer)
    }



    // MARK: - 交互

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let hit = item(at: point) else { return }
        switch hit {
        case .tool(let tool):
            selectedTool = (selectedTool == tool) ? nil : tool
            delegate?.toolBarDidChangeTool(selectedTool)
        case .more:
            delegate?.toolBarDidRequestPanel(.tools(configuration.overflowTools), anchor: visibleRect(of: hit))
        case .color:
            delegate?.toolBarDidRequestPanel(.colors(Self.colors), anchor: visibleRect(of: hit))
        case .width:
            // 官方把线宽 / 实虚线 / 颜色 Alpha 放在同一个「画笔设置」入口里
            delegate?.toolBarDidRequestPanel(.styles(widths: Self.widths,
                                                    dashes: Self.dashes,
                                                    alphas: Self.alphas),
                                            anchor: visibleRect(of: hit))
        case .action(let action):
            delegate?.toolBarDidPerform(action)
        }
    }

    /// 命中项在「可视条坐标」里的矩形（覆盖层按它定位二级面板，不含气泡区偏移）
    private func visibleRect(of item: SnipBarItem) -> CGRect {
        let rect = itemRects.first { $0.item == item }?.rect ?? .zero
        return rect.offsetBy(dx: -barOriginX, dy: -barOriginY)
    }

    /// 可视条在视图内的左边界（恒为 0：整条宽度就是条宽）
    private var barOriginX: CGFloat { 0 }
}
