import AppKit
import NetworkMonitorUI

// MARK: - 卡片阴影（容器层绘制）

/// 卡片阴影 —— 由卡片**下方**的容器统一绘制，参数化后任何卡片容器都能用
///
/// 为什么阴影不在卡片自己的 `draw` 里：视图绘制被 bounds 裁切、画不到卡外；
/// 而卡片自身 backing layer 的阴影在离屏快照（`cacheDisplay`）路径里不参与合成。
/// 在容器按同一个圆角矩形画阴影，既能溢出卡片，又不多一个视图（见 docs/踩坑/运行时/离屏快照里投影要靠像素差自证.md）。
struct DrawnCardShadow {

    /// 卡片圆角（阴影形状与卡片同圆角）
    var radius: CGFloat
    /// 设计给定的阴影不透明度（= 改造前 CALayer.shadowOpacity）
    var opacity: CGFloat
    /// 绘制内容的 alpha —— 阴影强度按内容 alpha 调制，故反算回「内容之上」的等效不透明度
    var contentAlpha: CGFloat
    /// CGContext 的模糊核尺度（= 可见扩散半径 × 2，CALayer.shadowRadius 与 CG blur 约 2 倍关系）
    var blur: CGFloat
    /// 阴影偏移（翻转坐标：正值向下）
    var offset: CGSize = CGSize(width: 0, height: 1)
    /// 阴影形状相对卡片矩形的内缩（露出的描边被裁掉时用 0.5）
    var inset: CGFloat = 0.5
    /// 绘制内容的填充色（阴影按它的 alpha 调制）
    var fillColor: NSColor = .black

    /// 围绕卡片矩形画阴影：只保留卡片外的区域
    ///
    /// - Parameters:
    ///   - rect: 卡片矩形（容器坐标）
    ///   - ctx: 当前绘图上下文
    ///   - bounds: 容器 bounds —— 卡片内区域被 even-odd 挖空，不会被阴影重复加深
    func draw(around rect: CGRect, in ctx: CGContext, clippingTo bounds: CGRect) {
        guard rect.width > 0, rect.height > 0, contentAlpha > 0.001 else { return }
        let shapeRect = DrawnShadowMath.shapeRect(for: rect, inset: inset)
        let shape = NSBezierPath(roundedRect: shapeRect, xRadius: radius, yRadius: radius)
        let outside = NSBezierPath(rect: bounds)
        outside.append(shape)
        outside.windingRule = .evenOdd

        ctx.saveGState()
        outside.addClip()
        ctx.setShadow(offset: offset,
                      blur: blur,
                      color: NSColor.black.withAlphaComponent(
                        DrawnShadowMath.shadowAlpha(opacity: opacity,
                                                    contentAlpha: contentAlpha)).cgColor)
        fillColor.withAlphaComponent(contentAlpha).setFill()
        shape.fill()
        ctx.restoreGState()
    }
}
