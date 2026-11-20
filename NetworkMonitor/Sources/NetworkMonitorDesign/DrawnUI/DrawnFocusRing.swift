import AppKit
import NetworkMonitorUI

// MARK: - 焦点环

/// 键盘焦点环 —— 行列表与整卡两处自绘焦点环共用的绘制
///
/// 两段的路径 API 刻意不同：行内焦点环沿用改造前的 `CGPath(roundedRect:)`，
/// 整卡焦点环沿用改造前的 `NSBezierPath(roundedRect:)`——同一矩形、同一线宽下
/// 两种路径构造的描边有 1px 级抗锯齿差（实测 60×60 圆角矩形 104px），换其中任一处都是纯风险、零收益。
@MainActor
public enum DrawnFocusRing {

    /// 行内焦点环（行列表）：内缩 1 / 1.5pt，圆角 4，1.5pt 强调色
    ///
    /// - Parameters:
    ///   - rect: 行矩形（flipped 坐标）
    ///   - color: 环色（默认取系统强调色）
    public static func drawRow(in rect: CGRect, color: NSColor = .controlAccentColor) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.addPath(DrawnInk.roundedPath(DrawnFocusRingMath.rowRect(for: rect), radius: 4))
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(1.5)
        ctx.strokePath()
    }

    /// 整卡焦点环：内缩 1，圆角 = 卡圆角 − 1，2pt
    ///
    /// - Parameters:
    ///   - bounds: 卡片矩形
    ///   - radius: 卡片圆角（环圆角取「卡圆角 − 1」，跟着内缩走）
    ///   - color: 环色（由调用方按其数据语义给，例如系统页取 CPU 蓝 50%）
    public static func drawCard(in bounds: CGRect, radius: CGFloat, color: NSColor) {
        let ringRadius = DrawnFocusRingMath.cardRadius(radius)
        let ring = NSBezierPath(roundedRect: DrawnFocusRingMath.cardRect(for: bounds),
                                xRadius: ringRadius,
                                yRadius: ringRadius)
        ring.lineWidth = 2
        color.setStroke()
        ring.stroke()
    }
}
