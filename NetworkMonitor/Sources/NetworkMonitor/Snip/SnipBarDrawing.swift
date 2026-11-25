import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 工具条基础绘制

/// 工具条与二级面板共用的按钮画法
///
/// 一级工具条与二级面板要画同一套按钮（选中态的圆角底、SF Symbols、颜色圆点、线宽条），
/// 抽到这里避免两处各写一遍——早期工具条宽度与布局就是这么分叉出 17pt 空白的。
enum SnipBarDrawing {

    /// 画一个工具按钮（SF Symbol，白色）
    ///
    /// inset 默认 6pt（30pt 按钮里图标 18pt）；常驻标签档按钮更大，传 1pt 让图标保持 20pt 左右。
    static func drawTool(_ tool: SnipTool, in rect: CGRect, alpha: CGFloat, inset: CGFloat = 6) {
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        guard let image = NSImage(systemSymbolName: tool.symbolName,
                                  accessibilityDescription: tool.displayName)?
            .withSymbolConfiguration(configuration) else {
            return
        }
        image.draw(in: rect.insetBy(dx: inset, dy: inset), from: .zero, operation: .sourceOver, fraction: alpha)
    }

    /// 画一个 SF Symbol（白色，按 alpha 淡化）—— 「更多」等非工具图标共用
    static func drawSymbol(_ name: String, in rect: CGRect, alpha: CGFloat,
                           description: String, inset: CGFloat = 9) {
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: description)?
            .withSymbolConfiguration(configuration) else {
            return
        }
        image.draw(in: rect.insetBy(dx: inset, dy: inset), from: .zero,
                   operation: .sourceOver, fraction: alpha)
    }

    /// 画格底 —— 选中 / 悬停两套选中语言的唯一落地处
    ///
    /// - 一级工具条（`.fill`）：整格反白，三档明度由 `SnipBarTone` 给出；
    /// - 二级面板（`.stroke`）：底只做同格调（选中 0.10 / 悬停 0.13），选中感交给
    ///   1.5pt 强调色描边 —— 与一级的整格反白区分开，两层选择才不会撞脸。
    ///
    /// 强调色直接用系统 `controlAccentColor`：主题 `.accent` 角色
    /// （`ThemeStyle` 的 `.systemAccent`）解析出来就是它，不另建令牌。
    static func drawSelection(isSelected: Bool,
                              isHovered: Bool,
                              in rect: CGRect,
                              style: SnipBarTone.SnipBarSelectionStyle) {
        guard isSelected || isHovered else { return }
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        switch style {
        case .fill:
            guard let fill = SnipBarTone.fillAlpha(isSelected: isSelected, isHovered: isHovered) else { return }
            NSColor.white.withAlphaComponent(fill).setFill()
            path.fill()
        case .stroke:
            NSColor.white.withAlphaComponent(isSelected
                ? SnipBarTone.panelSelectedFillAlpha
                : SnipBarTone.hoverFillAlpha).setFill()
            path.fill()
            guard isSelected else { return }
            NSColor.controlAccentColor.setStroke()
            path.lineWidth = SnipBarTone.selectionStrokeWidth
            path.stroke()
        }
    }

    /// 画一个颜色圆点（选中时加白色描边环）
    static func drawColorDot(_ color: SnipAnnotationColor, in rect: CGRect, isSelected: Bool) {
        let dotRect = rect.insetBy(dx: 3, dy: 3)
        NSColor(cgColor: color.cgColor)?.setFill()
        NSBezierPath(ovalIn: dotRect).fill()
        guard isSelected else { return }
        NSColor.white.withAlphaComponent(0.95).setStroke()
        let ring = NSBezierPath(ovalIn: dotRect.insetBy(dx: -2, dy: -2))
        ring.lineWidth = 1.5
        ring.stroke()
    }

    /// 画虚线 / 实线样本（一条短横线，虚线按线宽算间距，与渲染器同一口径）
    static func drawDashSample(dashed: Bool, in rect: CGRect, isSelected: Bool) {
        let y = rect.midY - 1
        let x0 = rect.minX + 6
        let x1 = rect.maxX - 6
        let alpha: CGFloat = isSelected ? 1 : 0.72
        if dashed {
            // 与 SnipAnnotationRenderer 的 setLineDash 同一节奏：段长 = 线宽 × 3、间距 = 线宽 × 2
            var x = x0
            NSColor.white.withAlphaComponent(alpha).setFill()
            while x < x1 {
                let segment = min(3 * 2, x1 - x)
                guard segment > 0 else { break }
                NSBezierPath(roundedRect: CGRect(x: x, y: y, width: segment, height: 2),
                             xRadius: 1, yRadius: 1).fill()
                x += segment + 2 * 2
            }
        } else {
            NSColor.white.withAlphaComponent(alpha).setFill()
            NSBezierPath(roundedRect: CGRect(x: x0, y: y, width: x1 - x0, height: 2),
                         xRadius: 1, yRadius: 1).fill()
        }
    }

    /// 透明度档的圆点 —— 圆点底下垫棋盘格
    ///
    /// 为什么必须垫：白底上画 100% / 75% / 50% / 25% / 0% 五个白色圆点，
    /// 前四个只是「灰一点的圆」，0% 那格干脆什么都没有 —— 用户看不出"这一档是透明的"，
    /// 反而以为是没画出来。棋盘格是"透明"的通用视觉符号（贴图窗的棋盘底同一套色值）。
    static func drawAlphaDot(alpha: CGFloat, in rect: CGRect, isSelected: Bool) {
        let dotRect = rect.insetBy(dx: 6, dy: 6)
        let path = NSBezierPath(ovalIn: dotRect)
        if let context = NSGraphicsContext.current?.cgContext {
            context.saveGState()
            path.addClip()
            // 圆点只有 28pt，用贴图窗那套 8pt 格子只剩 3×3，五档看起来一模一样。
            // 这里用 4pt 小格：格纹本身成为「透明」的密度信号，档位越低格纹露出越多。
            drawChecker(in: dotRect, in: context, cell: 4,
                        lightTone: 0.62, darkTone: 0.42)
            context.restoreGState()
        }
        NSColor.white.withAlphaComponent(min(max(alpha, 0), 1)).setFill()
        path.fill()
        // 环在低透明度档上要更亮，否则 0% 那格只剩一圈几乎看不见的淡边
        NSColor.white.withAlphaComponent(isSelected ? 0.95 : 0.55).setStroke()
        let ring = NSBezierPath(ovalIn: dotRect.insetBy(dx: -1, dy: -1))
        ring.lineWidth = isSelected ? 1.5 : 1
        ring.stroke()
    }

    /// 画棋盘格底（透明度条、半透明色点下面垫一层，才看得出「这里是透明的」）
    ///
    /// 格子边长与两档灰度默认复用贴图窗的 PinBoardBackgroundResolver，
    /// 同一屏里两处棋盘格必须是同一套（否则看起来像画错了）。
    /// - Parameters:
    ///   - cell: 格子边长；透明圆点用更小的格
    ///   - lightTone / darkTone: 两档灰度；透明圆点用中灰（近白棋盘上盖白笔几乎无差别）
    static func drawChecker(in rect: CGRect, in context: CGContext,
                            cell: CGFloat = PinBoardBackgroundResolver.cellSize,
                            lightTone: CGFloat = PinBoardBackgroundResolver.Tone.light,
                            darkTone: CGFloat = PinBoardBackgroundResolver.Tone.dark) {
        guard cell > 0 else { return }
        let light = NSColor(white: lightTone, alpha: 1)
        let dark = NSColor(white: darkTone, alpha: 1)
        let columns = Int((rect.width / cell).rounded(.up))
        let rows = Int((rect.height / cell).rounded(.up))
        for row in 0..<max(rows, 0) {
            for column in 0..<max(columns, 0) {
                let isLight = PinBoardBackgroundResolver.isLightCell(column: column, row: row)
                context.setFillColor((isLight ? light : dark).cgColor)
                context.fill(CGRect(x: rect.minX + CGFloat(column) * cell,
                                    y: rect.minY + CGFloat(row) * cell,
                                    width: cell,
                                    height: cell))
            }
        }
    }

    /// 画一个文字样本（字号档 / 加粗开关 / 字体族都用它）
    ///
    /// 用「写在格子里的一两个字符」而不是图标：字号与加粗本身就是该被看见的差异，
    /// 换成图标用户还得靠悬停气泡才知道点了会变成多大。
    static func drawTextSample(_ text: String, size: CGFloat, bold: Bool,
                               in rect: CGRect, alpha: CGFloat) {
        let font: NSFont = bold
            ? .boldSystemFont(ofSize: size)
            : .systemFont(ofSize: size)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white.withAlphaComponent(alpha),
        ]
        let string = text as NSString
        let bounds = string.size(withAttributes: attributes)
        string.draw(at: CGPoint(x: rect.midX - bounds.width / 2,
                                y: rect.midY - bounds.height / 2),
                    withAttributes: attributes)
    }

    /// 画一档线宽（一条按线宽值加粗的短横线）
    static func drawWidth(_ width: CGFloat, in rect: CGRect, isSelected: Bool) {
        let lineRect = CGRect(x: rect.minX + 5,
                              y: rect.midY - width / 2,
                              width: rect.width - 10,
                              height: width)
        NSColor.white.withAlphaComponent(isSelected ? 1 : 0.7).setFill()
        NSBezierPath(roundedRect: lineRect, xRadius: width / 2, yRadius: width / 2).fill()
    }
}
