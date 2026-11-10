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
    ///
    /// 缩放比以「捕获图实际像素尺寸 ÷ 屏幕点尺寸」为准，不采信 display.pixelSize：
    /// 本机（macOS 27、1512×982 点、2x 屏）实测 CGDisplayPixelsWide 返回 1512（点数而非像素数），
    /// 由它推出的 backingScale 是 1，于是选区的点坐标被当成像素坐标去裁剪，
    /// 截出来的内容整体偏到左上方（用户口径：「框选 A，截到的是 B，往左偏了几百」）。
    /// NetworkMonitorCore 不能 import AppKit，拿不到 convertRectToBacking，
    /// 因此以调用方给来的 imageSize 为唯一权威——2x 屏与 1x 屏都能自洽。
    public static func pixelRect(of rect: CGRect, in display: SnipDisplay, imageSize: CGSize) -> CGRect {
        let local = rect.intersection(display.frame)
        guard !local.isNull, local.width > 0, local.height > 0 else { return .zero }
        let scaleX = display.frame.width > 0 && imageSize.width > 0
            ? imageSize.width / display.frame.width
            : display.backingScale
        let scaleY = display.frame.height > 0 && imageSize.height > 0
            ? imageSize.height / display.frame.height
            : display.backingScale
        let pixel = CGRect(x: (local.minX - display.frame.minX) * scaleX,
                           y: (local.minY - display.frame.minY) * scaleY,
                           width: local.width * scaleX,
                           height: local.height * scaleY)
        return clamp(pixel.integral, to: CGRect(origin: .zero, size: imageSize))
    }
}
