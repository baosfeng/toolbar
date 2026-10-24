import AppKit
import NetworkMonitorCore

// MARK: - 工具条回调

@MainActor
protocol SnipToolBarViewDelegate: AnyObject {
    /// 切换工具；nil 表示回到「选区操作」模式
    func toolBarDidChangeTool(_ tool: SnipTool?)
    /// 切换颜色或线宽
    func toolBarDidChangeStyle(_ style: SnipAnnotationStyle)
}

// MARK: - 标注工具条

/// 选区下方的标注工具条 — 自绘按钮，避免在浮动覆盖层里放原生控件
@MainActor
final class SnipToolBarView: NSView {

    static let height: CGFloat = 40

    weak var delegate: SnipToolBarViewDelegate?

    private(set) var selectedTool: SnipTool?
    private(set) var style = SnipAnnotationStyle()

    private let tools = SnipTool.allCases
    private let colors: [SnipAnnotationColor] = [.red, .orange, .yellow, .green, .blue, .black, .white]
    private let widths: [CGFloat] = [2, 4, 8]

    private var toolRects: [(SnipTool, CGRect)] = []
    private var colorRects: [(SnipAnnotationColor, CGRect)] = []
    private var widthRects: [(CGFloat, CGRect)] = []

    private enum Metrics {
        static let padding: CGFloat = 8
        static let toolSide: CGFloat = 30
        static let toolGap: CGFloat = 3
        static let colorSide: CGFloat = 20
        static let colorGap: CGFloat = 3
        static let widthSide: CGFloat = 24
        static let widthGap: CGFloat = 3
        static let separatorGap: CGFloat = 8
    }

    override var isFlipped: Bool { true }

    /// 整条工具条的宽度
    static var preferredWidth: CGFloat {
        let tools = CGFloat(SnipTool.allCases.count)
        let widths = CGFloat(3)
        let colors = CGFloat(7)
        return Metrics.padding * 2
            + tools * Metrics.toolSide + (tools - 1) * Metrics.toolGap
            + Metrics.separatorGap * 2
            + colors * Metrics.colorSide + (colors - 1) * Metrics.colorGap
            + widths * Metrics.widthSide + (widths - 1) * Metrics.widthGap
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

    private func layoutRects() {
        toolRects.removeAll()
        colorRects.removeAll()
        widthRects.removeAll()

        var x = Metrics.padding
        let centerY = bounds.height / 2

        for tool in tools {
            toolRects.append((tool, CGRect(x: x, y: centerY - Metrics.toolSide / 2,
                                           width: Metrics.toolSide, height: Metrics.toolSide)))
            x += Metrics.toolSide + Metrics.toolGap
        }
        x += Metrics.separatorGap * 2 - Metrics.toolGap

        for color in colors {
            colorRects.append((color, CGRect(x: x, y: centerY - Metrics.colorSide / 2,
                                             width: Metrics.colorSide, height: Metrics.colorSide)))
            x += Metrics.colorSide + Metrics.colorGap
        }
        x += Metrics.separatorGap * 2 - Metrics.colorGap

        for width in widths {
            widthRects.append((width, CGRect(x: x, y: centerY - Metrics.widthSide / 2,
                                             width: Metrics.widthSide, height: Metrics.widthSide)))
            x += Metrics.widthSide + Metrics.widthGap
        }
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

        drawSeparator(at: toolRects.last?.1.maxX ?? 0, in: context)
        drawSeparator(at: colorRects.last?.1.maxX ?? 0, in: context)

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
        context.move(to: CGPoint(x: x + Metrics.separatorGap, y: 10))
        context.addLine(to: CGPoint(x: x + Metrics.separatorGap, y: bounds.height - 10))
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
    }
}
