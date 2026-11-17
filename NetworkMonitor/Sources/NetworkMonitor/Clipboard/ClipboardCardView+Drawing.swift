import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 整卡绘制

/// ClipboardCardView 的整卡绘制 —— 一次 draw 画完卡底、描边、卡头带、正文、meta、缩略图、星标与角标
///
/// 卡头带（来源染色）实现在 `ClipboardHeadBand.swift`；层序与改造前视图树一一对应（自下而上）：
/// 1. 卡底（controlBackgroundColor 0.72，圆角 12）；
/// 2. 常态描边（separatorColor 1pt，内缩半个线宽）；
/// 3. hover 提亮（白 6% 叠色 + label 45% 1.5pt 描边，alpha = hoverBlend）；
/// 4. 选中叠色（accent 5% 叠色 + accent 1.5pt 描边，alpha = selectionBlend）；
/// 5. 正文 / 图片占位（再往后是 meta 行）；
/// 6. 缩略图真图（覆盖正文区，0.2s 淡入）；
/// 7. 收藏星（meta 行内，切换时弹入）；
/// 8. Paste Stack 角标（内容区右上角，推进时弹入）。
///
/// 绘制发生在卡片的自绘内容图层（DrawnCanvasLayer）上：卡底与阴影同层，
/// 卡底盖住阴影在卡片内部的部分，阴影只在卡外可见——与改造前「底色子视图挂 CALayer 阴影」
/// 的合成结果同源，且离屏快照（cacheDisplay）与真实窗口两条渲染路径都能拍到阴影。
extension ClipboardCardView {

    /// 整卡绘制入口（由 DrawnCanvasLayer 在翻转上下文里回调）
    func drawCard(in bounds: CGRect) {
        // 卡底层（DrawnCardSurface：圆角 / 填充 / 叠色 / 描边三处卡片共用）
        DrawnCardSurface(rect: bounds,
                         radius: Self.cornerRadius,
                         fill: NSColor.controlBackgroundColor.withAlphaComponent(Self.backgroundAlpha)).draw()
        layer(inset: Self.borderWidth / 2, width: Self.borderWidth,
              stroke: NSColor.separatorColor, fill: nil, alpha: 1).draw()
        layer(inset: Self.activeBorderWidth / 2, width: Self.activeBorderWidth,
              stroke: NSColor.labelColor.withAlphaComponent(Self.hoverStrokeAlpha),
              fill: NSColor.white.withAlphaComponent(Self.hoverFillAlpha),
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
        // meta 在正文之后画：改造成本最低的等价做法（缩略图只覆盖正文区，不会压到 meta）
        drawMeta(item: item, in: bounds)
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
