import CoreGraphics

// MARK: - 贴图缩放锚点（纯逻辑，可单测）

/// 滚轮缩放时的锚点换算
///
/// 贴图窗此前固定以窗口中心缩放：光标停在某个细节上滚轮，那个细节会往中心漂，
/// 想放大看的地方反而跑掉了。Snipaste 的口径是「以鼠标指针为中心缩放」，
/// 换算收进这里的纯函数，贴图窗只负责把算出来的原点交给 setFrame。
///
/// 口径只有一条：**锚点在窗口内的归一化位置保持不变**。
/// 归一化位置不变 ⇔ 锚点下压着的那个内容点不动，这正是「以光标为锚」的手感来源。
public enum PinZoomAnchor {

    /// 默认锚点：窗口中心（键盘 + / - 与缩略图开关沿用它，行为与此前完全一致）
    public static func center(of frame: CGRect) -> CGPoint {
        CGPoint(x: frame.midX, y: frame.midY)
    }

    /// 把锚点夹回窗口矩形内（鼠标在窗口外时滚轮也会进来，锚点不能落在窗口外）
    public static func clamped(_ anchor: CGPoint, in frame: CGRect) -> CGPoint {
        guard frame.width > 0, frame.height > 0 else { return center(of: frame) }
        return CGPoint(x: min(max(anchor.x, frame.minX), frame.maxX),
                       y: min(max(anchor.y, frame.minY), frame.maxY))
    }

    /// 锚点在窗口内的归一化位置（0…1）；窗口尺寸非法时回落 0.5
    public static func normalized(_ anchor: CGPoint, in frame: CGRect) -> CGPoint {
        guard frame.width > 0, frame.height > 0 else { return CGPoint(x: 0.5, y: 0.5) }
        return CGPoint(x: (anchor.x - frame.minX) / frame.width,
                       y: (anchor.y - frame.minY) / frame.height)
    }

    /// 缩放后的新原点
    ///
    /// - Parameters:
    ///   - frame: 缩放前的窗口矩形（屏幕坐标）
    ///   - newSize: 缩放后的窗口尺寸
    ///   - anchor: 锚点（屏幕坐标；传 nil 用窗口中心）
    /// - Returns: 缩放后的窗口原点
    ///
    /// 算法：先把锚点夹回窗口内，取它的归一化位置 n，再让新窗口满足
    /// anchor = newOrigin + n × newSize，则锚点下的内容点缩放前后落在同一处。
    public static func origin(frame: CGRect, newSize: CGSize, anchor: CGPoint? = nil) -> CGPoint {
        let raw = anchor ?? center(of: frame)
        let point = clamped(raw, in: frame)
        let ratio = normalized(point, in: frame)
        return CGPoint(x: point.x - ratio.x * newSize.width,
                       y: point.y - ratio.y * newSize.height)
    }
}
