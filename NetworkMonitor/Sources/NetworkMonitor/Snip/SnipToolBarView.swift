import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 工具条回调

/// 工具条右侧的动作按钮
enum SnipBarAction: CaseIterable {
    case cancel
    case copy
    case save
    case pin

    var title: String {
        switch self {
        case .cancel: return "取消"
        case .copy: return "复制"
        case .save: return "保存"
        case .pin: return "贴图"
        }
    }

    /// 强调色按钮（主动作）
    var isPrimary: Bool { self == .copy }
}

@MainActor
protocol SnipToolBarViewDelegate: AnyObject {
    /// 切换工具；nil 表示回到「选区操作」模式
    func toolBarDidChangeTool(_ tool: SnipTool?)
    /// 切换颜色或线宽
    func toolBarDidChangeStyle(_ style: SnipAnnotationStyle)
    /// 点击右侧动作按钮（取消 / 复制 / 保存 / 贴顶）
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
/// 一级工具条只摆高频项：4 个常用工具 + 「更多」+ 当前颜色 + 当前线宽 + 4 个动作按钮。
/// 10 个工具全摆上来要 800pt 以上（比半个屏幕还宽），其余工具与全部颜色 / 线宽带
/// 收进二级面板（SnipToolPanelView）。
@MainActor
final class SnipToolBarView: NSView {

    static let height: CGFloat = SnipToolBarLayout.height

    weak var delegate: SnipToolBarViewDelegate?

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
    /// 实线 / 虚线两档（官方专业版「虚线/点线」能力）
    static let dashes: [Bool] = [false, true]
    /// 颜色透明度三档：不透明 / 半透明 / 淡（官方 Alpha 0–255 的常用档位）
    static let alphas: [CGFloat] = [1.0, 0.6, 0.3]
    /// 一级工具条常驻的工具
    static let primaryTools = SnipTool.primary
    /// 收进二级面板的工具
    static let overflowTools = SnipTool.overflow

    private var toolRects: [(SnipTool, CGRect)] = []
    private var moreRect: CGRect = .zero
    private var colorRect: CGRect = .zero
    private var widthRect: CGRect = .zero
    private var actionRects: [(SnipBarAction, CGRect)] = []
    /// 组间分隔线的 x 坐标（与按钮排布同源，避免两处各算一遍）
    private var dividerXs: [CGFloat] = []

    override var isFlipped: Bool { true }

    /// 整条工具条的宽度
    ///
    /// 宽度与按钮位置都由 SnipToolBarLayout 一次算出：早期实现里宽度与布局各写一遍累加式，
    /// 前者多算一段组间宽度、后者末尾多算一个组内间隙，右侧因此多出 17pt 空白，
    /// 按钮看着像被挤向左边。纯逻辑搬到 NetworkMonitorUI 后可被 TestRunner 直接断言。
    static var preferredWidth: CGFloat {
        layoutPlan.width
    }

    /// 当前工具条用到的布局参数（宽度与摆放共用，不各算一遍）
    static var layoutArguments: (toolCount: Int, colorCount: Int, widthCount: Int, actionCount: Int) {
        (primaryTools.count + 1, 1, 1, SnipBarAction.allCases.count)
    }

    /// 当前传入组件的布局计划
    private static var layoutPlan: SnipToolBarLayout.Plan {
        let args = layoutArguments
        return SnipToolBarLayout.plan(toolCount: args.toolCount,
                                      colorCount: args.colorCount,
                                      widthCount: args.widthCount,
                                      actionCount: args.actionCount)
    }

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: Self.preferredWidth, height: Self.height))
        wantsLayer = true
        setAccessibilityRole(.group)
        setAccessibilityLabel("截图标注工具条")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("不支持从 nib 创建")
    }

    // MARK: - 布局

    /// 按共享计划摆放（每帧重算，bounds 变化后仍然对齐）
    private func layoutRects() {
        let args = Self.layoutArguments
        let plan = SnipToolBarLayout.plan(toolCount: args.toolCount,
                                          colorCount: args.colorCount,
                                          widthCount: args.widthCount,
                                          actionCount: args.actionCount)
        let toolSlots = plan.toolRects
        toolRects = Array(zip(Self.primaryTools, toolSlots))
        // 工具组最后一个位置是「更多」
        moreRect = toolSlots.count > Self.primaryTools.count ? toolSlots[Self.primaryTools.count] : .zero
        colorRect = plan.colorRects.first ?? .zero
        widthRect = plan.widthRects.first ?? .zero
        actionRects = Array(zip(SnipBarAction.allCases, plan.actionRects))
        dividerXs = plan.dividerXs
    }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        layoutRects()
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let background = NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10)
        NSColor.black.withAlphaComponent(0.82).setFill()
        background.fill()

        for (tool, rect) in toolRects {
            let isSelected = tool == selectedTool
            if isSelected {
                NSColor.white.withAlphaComponent(0.22).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
            }
            SnipBarDrawing.drawTool(tool, in: rect, alpha: isSelected ? 1 : 0.72)
        }

        drawMoreButton()
        for x in dividerXs {
            drawSeparator(at: x, in: context)
        }

        // 当前颜色 / 线宽：一级只显示当前值，点开二级面板再换
        SnipBarDrawing.drawColorDot(style.color, in: colorRect, isSelected: false)
        SnipBarDrawing.drawWidth(style.lineWidth, in: widthRect, isSelected: true)

        for (action, rect) in actionRects {
            let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
            if action.isPrimary {
                NSColor.controlAccentColor.setFill()
                path.fill()
            } else {
                NSColor.white.withAlphaComponent(0.16).setFill()
                path.fill()
            }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.white
            ]
            let text = action.title as NSString
            let size = text.size(withAttributes: attributes)
            text.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
                      withAttributes: attributes)
        }
    }

    /// 「更多」按钮：当前工具在二级面板里时显示该工具图标（用户仍看得到自己在用什么）
    private func drawMoreButton() {
        guard moreRect.width > 0 else { return }
        let overflowSeleted = selectedTool.map { Self.overflowTools.contains($0) } ?? false
        if overflowSeleted {
            NSColor.white.withAlphaComponent(0.22).setFill()
            NSBezierPath(roundedRect: moreRect, xRadius: 6, yRadius: 6).fill()
        }
        if let tool = selectedTool, overflowSeleted {
            SnipBarDrawing.drawTool(tool, in: moreRect, alpha: 1)
            return
        }
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        if let image = NSImage(systemSymbolName: "chevron.down.2",
                               accessibilityDescription: "更多工具")?
            .withSymbolConfiguration(configuration) {
            image.draw(in: moreRect.insetBy(dx: 9, dy: 9), from: .zero, operation: .sourceOver, fraction: 0.72)
        }
    }

    private func drawSeparator(at x: CGFloat, in context: CGContext) {
        guard x > 0 else { return }
        context.saveGState()
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.18).cgColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: x, y: 9))
        context.addLine(to: CGPoint(x: x, y: bounds.height - 9))
        context.strokePath()
        context.restoreGState()
    }

    #if DEBUG
    /// 仅 DEBUG：取证时按位置取三个入口按钮的本地矩形
    var debugMoreRect: CGRect { layoutRects(); return moreRect }
    var debugColorRect: CGRect { layoutRects(); return colorRect }
    var debugWidthRect: CGRect { layoutRects(); return widthRect }
    #endif

    // MARK: - 交互

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        for (tool, rect) in toolRects where rect.contains(point) {
            selectedTool = (selectedTool == tool) ? nil : tool
            delegate?.toolBarDidChangeTool(selectedTool)
            return
        }
        if moreRect.contains(point) {
            delegate?.toolBarDidRequestPanel(.tools(Self.overflowTools), anchor: moreRect)
            return
        }
        if colorRect.contains(point) {
            delegate?.toolBarDidRequestPanel(.colors(Self.colors), anchor: colorRect)
            return
        }
        if widthRect.contains(point) {
            // 官方把线宽 / 实虚线 / 颜色 Alpha 放在同一个「画笔设置」入口里：
            // 点一级工具条上的当前线宽档就一次把三件事都调好，不用来回开三个盘面
            delegate?.toolBarDidRequestPanel(.styles(widths: Self.widths,
                                                     dashes: Self.dashes,
                                                     alphas: Self.alphas),
                                             anchor: widthRect)
            return
        }
        for (action, rect) in actionRects where rect.contains(point) {
            delegate?.toolBarDidPerform(action)
            return
        }
    }
}
