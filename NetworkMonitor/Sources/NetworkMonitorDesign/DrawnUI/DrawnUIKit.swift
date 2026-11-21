import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 自绘 UI 的基础原语

/// 自绘 UI 的公共原语 —— 路径、进度条、文本缓存入口
///
/// 定位：这是「组件库」的最底层，只做纯绘制，不持有业务状态。
/// 令牌一律转发 `PaneCardStyle`（换主题只改 `ThemeCatalog`，这里一行色值都不写），
/// 因此自绘组件与现有 AppKit 组件共用同一套设计语言与主题。
@MainActor
public enum DrawnInk {

    // MARK: 几何

    /// 圆角矩形路径（统一走这里，避免各处各写一套 cornerWidth）
    public static func roundedPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
        CGPath(roundedRect: rect,
               cornerWidth: min(radius, rect.height / 2),
               cornerHeight: min(radius, rect.height / 2),
               transform: nil)
    }

    // MARK: 进度条

    /// 轨道 + 填充的进度条（0…1，越界自动夹紧）
    ///
    /// - Parameters:
    ///   - rect: 进度条整体区域（高度即条高）
    ///   - progress: 0…1，超过范围会被夹到边界
    ///   - radius: 条的两端圆角，默认取高度一半（胶囊）
    public static func progressBar(in rect: CGRect,
                            progress: Double,
                            track: NSColor,
                            fill: NSColor,
                            radius: CGFloat? = nil) {
        guard rect.width > 0, rect.height > 0, let ctx = NSGraphicsContext.current?.cgContext else { return }
        let r = radius ?? rect.height / 2
        ctx.saveGState()
        ctx.addPath(roundedPath(rect, radius: r))
        ctx.setFillColor(track.cgColor)
        ctx.fillPath()
        let clamped = min(max(progress, 0), 1)
        let filled = CGRect(x: rect.minX, y: rect.minY, width: rect.width * CGFloat(clamped), height: rect.height)
        // 宽度不足以成圆角时不画，避免出现半像素黑边
        if filled.width >= 1 {
            ctx.addPath(roundedPath(filled, radius: min(r, filled.width / 2)))
            ctx.setFillColor(fill.cgColor)
            ctx.fillPath()
        }
        ctx.restoreGState()
    }

    /// 空描边条（不可得态占位：只有轮廓、没有填充）
    public static func outlineBar(in rect: CGRect, color: NSColor, radius: CGFloat? = nil) {
        guard rect.width > 0, rect.height > 0, let ctx = NSGraphicsContext.current?.cgContext else { return }
        let r = radius ?? rect.height / 2
        ctx.saveGState()
        ctx.addPath(roundedPath(rect.insetBy(dx: 0.5, dy: 0.5), radius: r))
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(1)
        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: 色点 / 分段条

    /// 行前色点（6pt 圆角块，与 Token 页图例色点同形）
    public static func swatch(in rect: CGRect, color: NSColor, radius: CGFloat = 1.5) {
        guard rect.width > 0, rect.height > 0 else { return }
        fill(rect, radius: radius, color: color)
    }

    /// 分段占比条（轨道 + 若干段，整体两端圆角、段内直角）
    ///
    /// 份额之和不要求等于 1：超出部分按顺序排在右侧被裁掉，不足则露出右侧轨道。
    public static func stackedBar(in rect: CGRect, shares: [Double], colors: [NSColor], track: NSColor) {
        guard rect.width > 0, rect.height > 0, let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.addPath(roundedPath(rect, radius: rect.height / 2))
        ctx.clip()
        ctx.setFillColor(track.cgColor)
        ctx.fill(rect)
        var offset = rect.minX
        for (index, share) in shares.enumerated() where share > 0 {
            let width = CGFloat(share) * rect.width
            guard width > 0.5 else { continue }
            ctx.setFillColor((index < colors.count ? colors[index] : track).cgColor)
            ctx.fill(CGRect(x: offset, y: rect.minY, width: width, height: rect.height))
            offset += width
        }
        ctx.restoreGState()
    }

    // MARK: 小色块

    /// 圆点（状态指示灯）
    public static func dot(in rect: CGRect, color: NSColor) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: rect)
    }

    /// 圆角底块（卡片 / 选中行 / 状态带）
    public static func fill(_ rect: CGRect, radius: CGFloat, color: NSColor) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.addPath(roundedPath(rect, radius: radius))
        ctx.setFillColor(color.cgColor)
        ctx.fillPath()
    }

    /// 1pt 分隔线（按屏幕缩放对齐，避免糊边）
    public static func hairline(from x0: CGFloat, to x1: CGFloat, y: CGFloat, color: NSColor) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let alignedY = (y * scale).rounded() / scale
        ctx.setFillColor(color.cgColor)
        ctx.fill(CGRect(x: x0, y: alignedY, width: x1 - x0, height: 1 / scale))
    }

    // MARK: 环 / 圆点

    /// 进度环 —— 从 12 点方向顺时针画 fraction（圆头端点）
    ///
    /// 弧用 NSBezierPath 画（角度语义 0=右、90=上、顺时针），与改造前 SystemRingView /
    /// SystemBatteryRingView 用的是同一段 API；在 flipped 视图里先局部翻正，
    /// 两种坐标系画出的圆环才能逐像素一致（实测换成 CGContext 弧会有 1–4 级抗锯齿差）。
    public static func ring(in rect: CGRect, fraction: Double, lineWidth: CGFloat,
                     color: NSColor, track: NSColor) {
        guard rect.width > 0, rect.height > 0 else { return }
        let radius = max(1, (min(rect.width, rect.height) - lineWidth) / 2)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        withUnflippedIfNeeded(around: rect) {
            let trackPath = NSBezierPath()
            trackPath.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
            trackPath.lineWidth = lineWidth
            track.setStroke()
            trackPath.stroke()

            let value = fraction.isFinite ? min(max(fraction, 0), 1) : 0
            guard value > 0 else { return }
            let arc = NSBezierPath()
            arc.appendArc(withCenter: center, radius: radius,
                          startAngle: 90, endAngle: 90 - 360 * CGFloat(value), clockwise: true)
            arc.lineWidth = lineWidth
            arc.lineCapStyle = .round
            color.setStroke()
            arc.stroke()
        }
    }

    /// 圆点（可带 1pt 内边）—— 浅底上 systemGreen / systemYellow 这类颜色对比不足 3:1，
    /// 用一圈描边把它从底上「框」出来，而不是把颜色调深（调深就是混色）
    ///
    /// 与原生 WiFiSignalDotView / SystemPressureDotView 同一段 NSBezierPath 绘制：
    /// 圆取 rect 内缩半个像素，描边压在圆心上（不额外内缩）。
    public static func circle(in rect: CGRect, fill: NSColor, stroke: NSColor? = nil, lineWidth: CGFloat = 1) {
        guard rect.width > 0, rect.height > 0 else { return }
        let oval = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
        fill.setFill()
        oval.fill()
        guard let stroke else { return }
        oval.lineWidth = lineWidth
        stroke.setStroke()
        oval.stroke()
    }

    /// 在 flipped 上下文里按「非 flipped」语义绘制
    ///
    /// 原生组件（SystemRingView / WiFiSignalDotView 等）都是非 flipped 视图，
    /// 自绘卡片统一 flipped；局部翻正后就能直接复用同一段路径代码。
    /// 位图绘制同样要用它：文本绘制自己会翻正，`NSImage.draw(in:from:operation:fraction:)` 不会，
    /// 卡片缩略图与详情区缩略图都靠这一处翻正（镜像轴取值由 `DrawnUnflip` 给出，不另写一套）。
    /// internal 而非 private：剪贴板卡片（`ClipboardCardView+Resources.swift`）跨文件复用。
    public static func withUnflippedIfNeeded(around rect: CGRect, _ body: () -> Void) {
        let flipped = NSGraphicsContext.current?.isFlipped == true
        guard let transform = DrawnUnflip.transform(around: rect, contextIsFlipped: flipped),
              let ctx = NSGraphicsContext.current?.cgContext else {
            body()
            return
        }
        ctx.saveGState()
        ctx.concatenate(transform)
        body()
        ctx.restoreGState()
    }
}
