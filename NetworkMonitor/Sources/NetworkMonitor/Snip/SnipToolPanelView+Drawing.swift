import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 二级面板条目绘制

/// 面板里每个格子怎么画 —— 从 SnipToolPanelView 拆出（主文件守住单文件体积门禁）
///
/// 四种盘面各自有一套画法：工具图标 / 颜色圆点 / 线宽条与线型样本 / 字号样本，
/// 但它们的**选中语言**是一致的（浅底 + 强调色描边），因此外壳仍留在主文件。
extension SnipToolPanelView {

    /// 单个条目（工具图标 / 颜色圆点 / 线宽条 / 线型样本 / 透明度圆点 / 字号样本）
    func drawItem(at index: Int, in rect: CGRect, isSelected: Bool, alpha: CGFloat) {
        let iconRect = labelMode.showsPersistentLabel
            ? CGRect(x: rect.midX - 11, y: rect.minY + 3, width: 22, height: 22)
            : rect
        switch content {
        case .tools(let tools) where tools.indices.contains(index):
            SnipBarDrawing.drawTool(tools[index], in: iconRect, alpha: alpha,
                                    inset: labelMode.showsPersistentLabel ? 1 : 6)
        case .colors(let colors) where colors.indices.contains(index):
            // 面板里的色点是一组可选项：只有真正选中的那一枚带环
            SnipBarDrawing.drawColorDot(colors[index], in: iconRect,
                                        isSelected: SnipBarTone.colorDotRingVisible(isCurrentColor: isSelected))
        case .colors(let colors) where index == colors.count:
            // 末尾是「自定义」：用一个彩色环图标表达「可以调出任意颜色」
            SnipBarDrawing.drawSymbol("eyedropper.halffull", in: iconRect, alpha: alpha,
                                      description: "自定义颜色")
        case .widths(let widths) where widths.indices.contains(index):
            SnipBarDrawing.drawWidth(widths[index], in: iconRect, isSelected: isSelected)
        case .styles(let widths, let dashes, let alphas):
            drawStyleItem(widths: widths, dashes: dashes, alphas: alphas,
                          index: index, rect: iconRect, isSelected: isSelected)
        case .textStyles(let sizes, let bold, let family):
            drawTextStyleItem(sizes: sizes, bold: bold, family: family,
                              index: index, rect: iconRect, isSelected: isSelected)
        default:
            break
        }
    }

    /// 画笔样式盘的单项：线宽档 → 粗细条、−/+ → 步进符号、虚线 → 虚线段、透明度 → 半透明圆点
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
        let afterWidths = index - widths.count
        if afterWidths < SnipPanelContent.stylesStepCount {
            // 连续微调：档位之外的值靠这两格走，线宽本身是 1–40 的连续值
            SnipBarDrawing.drawSymbol(afterWidths == 0 ? "minus" : "plus",
                                      in: rect, alpha: isSelected ? 1 : 0.72,
                                      description: afterWidths == 0 ? "线宽减一" : "线宽加一")
            return
        }
        let offset = afterWidths - SnipPanelContent.stylesStepCount
        if dashes.indices.contains(offset) {
            SnipBarDrawing.drawDashSample(dashed: dashes[offset], in: rect, isSelected: isSelected)
            return
        }
        let alphaIndex = offset - dashes.count
        if alphas.indices.contains(alphaIndex) {
            SnipBarDrawing.drawAlphaDot(alpha: alphas[alphaIndex], in: rect, isSelected: isSelected)
        }
    }

    /// 文字样式盘的单项：字号「A」样本（按档位放大）、加粗「B」、字体族首字
    private func drawTextStyleItem(sizes: [CGFloat],
                                   bold: Bool,
                                   family: SnipTextFamily,
                                   index: Int,
                                   rect: CGRect,
                                   isSelected: Bool) {
        if sizes.indices.contains(index) {
            // 字号样本：把档位区间线性映射到 9…24pt 的绘制字号。
            // 直接按真实字号画会两头崩（12pt 太小、56pt 撑破格子），
            // 而按 0…最大 归一又会让前四档挤成 9/9.5/10/10.5（实测肉眼无差别）。
            // 以「档位表自身的首尾」为分母，六档落在 9 / 10.5 / 12 / 14.5 / 18.4 / 24。
            let smallest = sizes.first ?? SnipTextStyle.fontSizePresets.first ?? 12
            let largest = sizes.last ?? SnipTextStyle.fontSizePresets.last ?? 56
            let ratio = max(largest - smallest, 1)
            let size = 9 + ((sizes[index] - smallest) / ratio) * 15
            SnipBarDrawing.drawTextSample("A", size: min(max(size, 9), 24), bold: false,
                                          in: rect, alpha: isSelected ? 1 : 0.72)
            return
        }
        if index == sizes.count {
            // 加粗开关：字形本身就是「粗」，且只有它带加粗
            SnipBarDrawing.drawTextSample("B", size: 15, bold: true,
                                          in: rect, alpha: isSelected ? 1 : 0.72)
            return
        }
        let familyIndex = index - sizes.count - 1
        let families = SnipTextFamily.allCases
        guard families.indices.contains(familyIndex) else { return }
        // 族格只用「选中描边」表达状态，不拿加粗当选中标记 ——
        // 加粗是另一根旋钮（B 那一格），两者混用会让人以为「选了默认族就是加粗」
        SnipBarDrawing.drawTextSample(families[familyIndex].panelInitial,
                                      size: 15,
                                      bold: false,
                                      in: rect,
                                      alpha: isSelected ? 1 : 0.72)
    }

    /// 常驻标签：图标下方 9.5pt 名称
    func drawPersistentLabel(at index: Int, in rect: CGRect) {
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
    func drawBubble(at index: Int, over rect: CGRect) {
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
}
