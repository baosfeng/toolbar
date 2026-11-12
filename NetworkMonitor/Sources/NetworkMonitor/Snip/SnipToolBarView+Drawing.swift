import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 工具条绘制（含文字提示三档）

/// 从主类拆出：绘制细节（圆角底、图标、颜色圆点、线宽条、气泡、常驻标签）
///
/// 文字提示的三档全部在这里落地：
/// - `iconOnly`：与既有外观一致，只有图标；
/// - `hover`（默认）：悬停的按钮提亮 + 上方弹气泡「名称 · 快捷键」，条高不变；
/// - `always`：每个按钮下方常驻 9.5pt 标签，条高 40 → 50pt。
extension SnipToolBarView {

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // 可视条底：整条只有可视条有底色，气泡区保持透明
        let barRect = CGRect(x: 0, y: barOriginY, width: bounds.width, height: barHeight)
        NSColor.black.withAlphaComponent(0.82).setFill()
        NSBezierPath(roundedRect: barRect, xRadius: 10, yRadius: 10).fill()

        for (index, entry) in itemRects.enumerated() {
            let isSelected = isSelected(entry.item)
            let isHovered = index == hoveredIndex && configuration.labelMode.showsHoverBubble
            // 悬停提亮：与选中态同色但更淡，提示「这里可以点」而不是「已选中」
            if isSelected || isHovered {
                NSColor.white.withAlphaComponent(isSelected ? 0.22 : 0.14).setFill()
                NSBezierPath(roundedRect: entry.rect, xRadius: 6, yRadius: 6).fill()
            }
            drawItem(entry.item, in: entry.rect, isSelected: isSelected,
                     alpha: isSelected ? 1 : (isHovered ? 0.95 : 0.72))
        }

        for x in dividerXs {
            drawSeparator(at: x, in: context)
        }

        if configuration.labelMode.showsPersistentLabel {
            for entry in itemRects {
                drawPersistentLabel(for: entry.item, in: entry.rect)
            }
        }
        // 二级面板展开时不画气泡：气泡正好落在面板底下，只会露出一截黑边
        if configuration.labelMode.showsHoverBubble,
           !isPanelOpen,
           let hovered = hoveredItem(),
           let rect = itemRects.first(where: { $0.item == hovered })?.rect {
            drawBubble(for: hovered, over: rect)
        }
    }

    /// 画一个项（图标 / 颜色圆点 / 线宽条 / 动作文字）
    private func drawItem(_ item: SnipBarItem, in rect: CGRect, isSelected: Bool, alpha: CGFloat) {
        switch item {
        case .tool(let tool):
            // 常驻标签档：图标占上半区、标签占下半区，图标按 20pt 画（不随按钮变宽而膨胀）
            let iconRect = configuration.labelMode.showsPersistentLabel
                ? CGRect(x: rect.midX - 11, y: rect.minY + 3, width: 22, height: 22)
                : rect
            SnipBarDrawing.drawTool(tool, in: iconRect, alpha: alpha,
                                    inset: configuration.labelMode.showsPersistentLabel ? 1 : 6)
        case .more:
            // 当前工具在二级面板里时显示该工具图标（用户仍看得到自己在用什么）
            if let tool = selectedTool, configuration.overflowTools.contains(tool) {
                SnipBarDrawing.drawTool(tool, in: rect, alpha: 1)
            } else {
                let symbolRect = configuration.labelMode.showsPersistentLabel
                ? CGRect(x: rect.midX - 11, y: rect.minY + 3, width: 22, height: 22)
                : rect
            SnipBarDrawing.drawSymbol("chevron.down.2", in: symbolRect, alpha: alpha,
                                      description: "更多工具",
                                      inset: configuration.labelMode.showsPersistentLabel ? 3 : 9)
            }
        case .color:
            SnipBarDrawing.drawColorDot(style.color, in: colorDotRect(in: rect), isSelected: false)
        case .width:
            let widthRect = configuration.labelMode.showsPersistentLabel
                ? CGRect(x: rect.midX - 12, y: rect.minY + 12, width: 24, height: 24)
                : rect
            SnipBarDrawing.drawWidth(style.lineWidth, in: widthRect, isSelected: true)
        case .action(let action):
            drawAction(action, in: rect, alpha: alpha)
        }
    }

    /// 颜色圆点按档位取尺寸：常驻标签档给出 20pt 圆点，仅图标档沿用 20pt
    private func colorDotRect(in rect: CGRect) -> CGRect {
        let side = SnipToolBarLayout.colorSide
        return CGRect(x: rect.midX - side / 2,
                      y: configuration.labelMode.showsPersistentLabel ? rect.minY + 12 : rect.midY - side / 2,
                      width: side, height: side)
    }

    /// 动作按钮：强调色底 + 文字（文字本身就是最直接的描述，不再另加气泡）
    private func drawAction(_ action: SnipBarAction, in rect: CGRect, alpha: CGFloat) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        if action.isPrimary {
            NSColor.controlAccentColor.withAlphaComponent(alpha).setFill()
        } else {
            NSColor.white.withAlphaComponent(0.16 * alpha).setFill()
        }
        path.fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(alpha)
        ]
        let text = action.title as NSString
        let size = text.size(withAttributes: attributes)
        text.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
                  withAttributes: attributes)
    }

    /// 常驻标签：图标下方 9.5pt 文字，超宽自动压缩（不换行，免得行高漂移）
    private func drawPersistentLabel(for item: SnipBarItem, in rect: CGRect) {
        let text = labelText(for: item)
        guard !text.isEmpty else { return }
        var attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9.5, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.62),
        ]
        let width = rect.width
        let string = text as NSString
        var size = string.size(withAttributes: attributes)
        if size.width > width {
            let factor = max(width / max(size.width, 1), 0.6)
            attributes[.font] = NSFont.systemFont(ofSize: 9.5 * factor, weight: .regular)
            size = string.size(withAttributes: attributes)
        }
        string.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.maxY - size.height - 1),
                    withAttributes: attributes)
    }

    /// 悬停气泡：黑底白字，内容为「名称 · 快捷键」，贴在被悬停按钮正上方
    private func drawBubble(for item: SnipBarItem, over rect: CGRect) {
        let text = bubbleText(for: item)
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
        // 气泡水平居中于按钮，整条两端不出界
        var originX = rect.midX - bubbleSize.width / 2
        originX = min(max(originX, 2), max(bounds.width - bubbleSize.width - 2, 2))
        let originY = max(barOriginY - bubbleSize.height - 4, 0)
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

    /// 按钮是否处于「已选中」状态（工具看当前工具，动作看主按钮）
    func isSelected(_ item: SnipBarItem) -> Bool {
        switch item {
        case .tool(let tool): return tool == selectedTool
        case .more: return selectedTool.map { configuration.overflowTools.contains($0) } ?? false
        case .color, .width, .action: return false
        }
    }

    /// 常驻标签文案：工具用中文名，颜色 / 线宽直接写当前值，动作写标题
    func labelText(for item: SnipBarItem) -> String {
        switch item {
        case .tool(let tool): return tool.displayName
        case .more: return "更多"
        case .color: return SnipAnnotationColorNaming.name(for: style.color)
        case .width: return "线宽 \(Int(style.lineWidth.rounded()))"
        case .action(let action): return action.title
        }
    }

    /// 气泡文案：名称 + 快捷键（动作按钮的标题已写在按钮上，气泡只补快捷键）
    func bubbleText(for item: SnipBarItem) -> String {
        switch item {
        case .tool(let tool):
            return tool.displayName
        case .more:
            return "更多工具（\(configuration.overflowTools.count) 个）"
        case .color:
            return "颜色 · \(SnipAnnotationColorNaming.name(for: style.color))"
        case .width:
            return "线宽 · \(Int(style.lineWidth.rounded())) pt"
        case .action(let action):
            return "\(action.title)  \(action.shortcutText)"
        }
    }

    private func drawSeparator(at x: CGFloat, in context: CGContext) {
        guard x > 0 else { return }
        context.saveGState()
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.18).cgColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: x, y: barOriginY + 9))
        context.addLine(to: CGPoint(x: x, y: barOriginY + barHeight - 9))
        context.strokePath()
        context.restoreGState()
    }

}
