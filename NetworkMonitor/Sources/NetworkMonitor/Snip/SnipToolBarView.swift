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
}

// MARK: - 标注工具条

/// 选区下方的标注工具条 — 自绘按钮，避免在浮动覆盖层里放原生控件
@MainActor
final class SnipToolBarView: NSView {

    static let height: CGFloat = SnipToolBarLayout.height

    weak var delegate: SnipToolBarViewDelegate?

    /// 放宽为 internal：DEBUG 取证要在离屏渲染里摆出「已选中」状态
    var selectedTool: SnipTool?
    private(set) var style = SnipAnnotationStyle()

    /// 仅 DEBUG：离屏取证时设置已选中的颜色 / 线宽
    #if DEBUG
    func debugSetStyle(_ newStyle: SnipAnnotationStyle) {
        style = newStyle
        needsDisplay = true
    }
    #endif

    private let tools = SnipTool.allCases
    private let colors: [SnipAnnotationColor] = [.red, .orange, .yellow, .green, .blue, .black, .white]
    private let widths: [CGFloat] = [2, 4, 8]

    private var toolRects: [(SnipTool, CGRect)] = []
    private var colorRects: [(SnipAnnotationColor, CGRect)] = []
    private var widthRects: [(CGFloat, CGRect)] = []
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

    /// 当前传入组件的布局计划
    private static var layoutPlan: SnipToolBarLayout.Plan {
        SnipToolBarLayout.plan(toolCount: SnipTool.allCases.count,
                               colorCount: 7,
                               widthCount: 3,
                               actionCount: SnipBarAction.allCases.count)
    }

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: Self.preferredWidth, height: Self.height))
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("不支持从 nib 创建")
    }

    // MARK: - 布局

    /// 按共享计划摆放（每帧重算，bounds 变化后仍然对齐）
    private func layoutRects() {
        let plan = SnipToolBarLayout.plan(toolCount: tools.count,
                                          colorCount: colors.count,
                                          widthCount: widths.count,
                                          actionCount: SnipBarAction.allCases.count)
        toolRects = Array(zip(tools, plan.toolRects))
        colorRects = Array(zip(colors, plan.colorRects))
        widthRects = Array(zip(widths, plan.widthRects))
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
            drawSymbol(for: tool, in: rect.insetBy(dx: 6, dy: 6),
                       alpha: isSelected ? 1 : 0.72)
        }

        for x in dividerXs {
            drawSeparator(at: x, in: context)
        }

        // 动作按钮：复制用强调色，其余灰色描边
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

        for (color, rect) in colorRects {
            let dotRect = rect.insetBy(dx: 3, dy: 3)
            NSColor(cgColor: color.cgColor)?.setFill()
            NSBezierPath(ovalIn: dotRect).fill()
            if color == style.color {
                NSColor.white.withAlphaComponent(0.95).setStroke()
                let ring = NSBezierPath(ovalIn: dotRect.insetBy(dx: -2, dy: -2))
                ring.lineWidth = 1.5
                ring.stroke()
            }
        }

        for (width, rect) in widthRects {
            let isSelected = width == style.lineWidth
            if isSelected {
                NSColor.white.withAlphaComponent(0.22).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
            }
            let lineRect = CGRect(x: rect.minX + 5, y: rect.midY - width / 2,
                                  width: rect.width - 10, height: width)
            NSColor.white.withAlphaComponent(isSelected ? 1 : 0.7).setFill()
            NSBezierPath(roundedRect: lineRect, xRadius: width / 2, yRadius: width / 2).fill()
        }
    }

    private func drawSymbol(for tool: SnipTool, in rect: CGRect, alpha: CGFloat) {
        let name = tool.symbolName
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: tool.displayName)?
            .withSymbolConfiguration(configuration) else {
            return
        }
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: alpha)
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

    // MARK: - 交互

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        for (tool, rect) in toolRects where rect.contains(point) {
            selectedTool = (selectedTool == tool) ? nil : tool
            delegate?.toolBarDidChangeTool(selectedTool)
            needsDisplay = true
            return
        }
        for (color, rect) in colorRects where rect.contains(point) {
            style.color = color
            delegate?.toolBarDidChangeStyle(style)
            needsDisplay = true
            return
        }
        for (width, rect) in widthRects where rect.contains(point) {
            style.lineWidth = width
            delegate?.toolBarDidChangeStyle(style)
            needsDisplay = true
            return
        }
        for (action, rect) in actionRects where rect.contains(point) {
            delegate?.toolBarDidPerform(action)
            return
        }
    }
}
