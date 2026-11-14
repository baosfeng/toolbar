import AppKit
import NetworkMonitorCore

// MARK: - 自绘 UI 的基础原语

/// 自绘 UI 的公共原语 —— 路径、进度条、文本缓存入口
///
/// 定位：这是「组件库」的最底层，只做纯绘制，不持有业务状态。
/// 令牌一律转发 `PaneCardStyle`（换主题只改 `ThemeCatalog`，这里一行色值都不写），
/// 因此自绘组件与现有 AppKit 组件共用同一套设计语言与主题。
@MainActor
enum DrawnInk {

    // MARK: 几何

    /// 圆角矩形路径（统一走这里，避免各处各写一套 cornerWidth）
    static func roundedPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
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
    static func progressBar(in rect: CGRect,
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

    // MARK: 小色块

    /// 圆点（状态指示灯）
    static func dot(in rect: CGRect, color: NSColor) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: rect)
    }

    /// 圆角底块（卡片 / 选中行 / 状态带）
    static func fill(_ rect: CGRect, radius: CGFloat, color: NSColor) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.addPath(roundedPath(rect, radius: radius))
        ctx.setFillColor(color.cgColor)
        ctx.fillPath()
    }

    /// 1pt 分隔线（按屏幕缩放对齐，避免糊边）
    static func hairline(from x0: CGFloat, to x1: CGFloat, y: CGFloat, color: NSColor) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let alignedY = (y * scale).rounded() / scale
        ctx.setFillColor(color.cgColor)
        ctx.fill(CGRect(x: x0, y: alignedY, width: x1 - x0, height: 1 / scale))
    }
}
