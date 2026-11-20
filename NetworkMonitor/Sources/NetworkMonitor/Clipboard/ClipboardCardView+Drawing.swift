import AppKit
import NetworkMonitorCore
import NetworkMonitorDesign
import NetworkMonitorUI

// MARK: - 整卡绘制

/// ClipboardCardView 的整卡绘制 —— 一次 draw 画完卡底、描边、卡头带、卡身、卡脚、缩略图与角标
///
/// 层序（自下而上）：卡底 → 常态描边 → hover 提亮 → 选中叠色 → 卡头带 → 卡身 → 卡脚 →
/// 缩略图 → 收藏星 → 栈角标。
/// 版式对标 Paste 的「彩色卡头 + 白卡身 + 卡脚」三段式：
/// 卡头 26pt（来源色 + 类型 + 相对时间 + App 图标）、卡身（正文 / 缩略图）、
/// 卡脚（标题 + 来源，上方一条发丝线）。
/// 绘制发生在 DrawnCanvasLayer 上：卡底与阴影同层，离屏快照（cacheDisplay）与真实窗口
/// 两条渲染路径都能拍到阴影。
extension ClipboardCardView {

    /// 整卡绘制入口（由 DrawnCanvasLayer 在翻转上下文里回调）
    func drawCard(in bounds: CGRect) {
        // 卡底层（DrawnCardSurface：圆角 / 填充 / 叠色 / 描边三处卡片共用）
        DrawnCardSurface(rect: bounds,
                         radius: Self.cornerRadius,
                         fill: PaneCardStyle.cardFill,
                         stroke: PaneCardStyle.hairline,
                         lineWidth: Self.borderWidth).draw()
        layer(inset: Self.hoverBorderWidth / 2, width: Self.hoverBorderWidth,
              stroke: PaneCardStyle.primaryText.withAlphaComponent(Self.hoverStrokeAlpha),
              fill: PaneCardStyle.primaryText.withAlphaComponent(Self.hoverFillAlpha),
              alpha: hoverBlend.value).draw()
        layer(inset: Self.activeBorderWidth / 2, width: Self.activeBorderWidth,
              stroke: .controlAccentColor,
              fill: NSColor.controlAccentColor.withAlphaComponent(Self.selectionFillAlpha),
              alpha: selectionBlend.value).draw()
        guard let item else { return }
        drawHeadBand(item: item, in: bounds)
        let body = ClipboardCardGeometry.bodyRect(in: bounds)
        if item.kind == .image {
            drawImageBody(item: item, in: body)
        } else {
            drawTextBody(item: item, in: body)
        }
        drawFooter(item: item, in: bounds)
        if item.kind == .image { drawThumbnailImage(in: body) }
        drawStar(item: item, in: bounds)
        drawStackBadge(item: item, in: bounds)
    }

    // MARK: 叠色与描边层

    /// 一层「叠色 + 描边」——对应改造前的 ClipboardCardHighlightView.draw
    ///
    /// - Parameters:
    ///   - inset: 描边内缩（= 半个线宽，避免被视图边界裁掉）
    ///   - width: 线宽
    ///   - stroke: 描边色
    ///   - fill: 叠色（nil = 不叠色）
    ///   - alpha: 整层不透明度（过渡值；改造前是视图 alphaValue）
    private func layer(inset: CGFloat, width: CGFloat, stroke: NSColor,
                       fill: NSColor?, alpha: CGFloat) -> DrawnCardSurface {
        DrawnCardSurface(rect: bounds.insetBy(dx: inset, dy: inset),
                         radius: Self.cornerRadius,
                         fill: fill,
                         stroke: stroke,
                         lineWidth: width,
                         alpha: alpha)
    }
}