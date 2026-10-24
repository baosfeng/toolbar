import CoreGraphics

// MARK: - 选区坐标换算

/// 选区坐标换算 — 纯函数，覆盖多屏、Retina、负坐标副屏
///
/// 坐标系约定：全局点坐标一律为 CG 坐标（原点在主屏左上，y 向下）；
/// AppKit 的屏幕矩形（左下原点）必须先经 cgRect(fromAppKit:) 转换。
public enum SelectionGeometry {

    /// 由拖拽起止点得到正矩形
    public static func normalize(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(x: min(start.x, end.x),
               y: min(start.y, end.y),
               width: abs(end.x - start.x),
               height: abs(end.y - start.y))
    }

    /// 把矩形夹取到边界内；完全不相交时返回 .zero
    public static func clamp(_ rect: CGRect, to bounds: CGRect) -> CGRect {
        let result = rect.intersection(bounds)
        return result.isNull ? .zero : result
    }

    /// 所有屏幕的并集（全局 CG 坐标）
    public static func unionFrame(of displays: [SnipDisplay]) -> CGRect {
        displays.reduce(CGRect.null) { $0.union($1.frame) }
    }

    /// 命中点所在屏幕；多屏重叠时返回首个包含该点的屏
    public static func display(containing point: CGPoint, in displays: [SnipDisplay]) -> SnipDisplay? {
        displays.first { $0.frame.contains(point) }
    }

    /// AppKit 屏幕矩形（左下原点）转全局 CG 矩形（左上原点）
    public static func cgRect(fromAppKit frame: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: frame.origin.x,
               y: primaryHeight - frame.origin.y - frame.height,
               width: frame.width,
               height: frame.height)
    }

    /// 全局 CG 矩形转 AppKit 屏幕矩形（左下原点），用于给覆盖层窗口定 frame
    public static func appKitRect(fromCG frame: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: frame.origin.x,
               y: primaryHeight - frame.origin.y - frame.height,
               width: frame.width,
               height: frame.height)
    }

    /// 选区在指定屏幕捕获图中的像素矩形；跨屏时只取与该屏的交叠部分
    public static func pixelRect(of rect: CGRect, in display: SnipDisplay, imageSize: CGSize) -> CGRect {
        let local = rect.intersection(display.frame)
        guard !local.isNull, local.width > 0, local.height > 0 else { return .zero }
        let scale = display.backingScale
        let pixel = CGRect(x: (local.minX - display.frame.minX) * scale,
                           y: (local.minY - display.frame.minY) * scale,
                           width: local.width * scale,
                           height: local.height * scale)
        return clamp(pixel.integral, to: CGRect(origin: .zero, size: imageSize))
    }
}
