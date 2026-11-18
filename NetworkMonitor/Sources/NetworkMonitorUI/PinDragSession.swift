import Foundation

// MARK: - 贴图窗拖动会话（纯逻辑，可单测）

/// 一次「按住左键移动窗口」的位移计算
///
/// 为什么不交给 `NSWindow.performDrag(with:)`：贴图窗是 `.nonactivatingPanel`，
/// 点击它**不会把 App 激活**；而 performDrag 依赖 Window Server 的窗口拖动会话，
/// 在 App 非活跃时是静默空操作（实测位移恒为 0，见交接文档）。
/// 因此拖动改为在这里自己算：按住点记下窗口原点与鼠标全局位置，
/// 之后每个 mouseDragged 用「鼠标位移」平移窗口原点。纯函数便于单测。
public struct PinDragSession: Equatable, Sendable {

    /// 按下时的窗口原点（屏幕全局坐标）
    public let startOrigin: CGPoint
    /// 按下时的鼠标位置（屏幕全局坐标）
    public let startMouse: CGPoint

    public init(startOrigin: CGPoint, startMouse: CGPoint) {
        self.startOrigin = startOrigin
        self.startMouse = startMouse
    }

    /// 鼠标移动到 `mouse` 时窗口应该在的原点
    ///
    /// 位移按「当前鼠标 − 按下鼠标」直接加在起始原点上，而不是累加上一帧，
    /// 这样丢帧、合并事件都不会积累误差。
    public func origin(forMouse mouse: CGPoint) -> CGPoint {
        CGPoint(x: startOrigin.x + (mouse.x - startMouse.x),
                y: startOrigin.y + (mouse.y - startMouse.y))
    }

    /// 该次移动是否已经越过系统拖动阈值（小于阈值当作单击，不挪窗口）
    ///
    /// 阈值取 3pt：与 AppKit 的拖动判定同量级，避免手一抖就把贴图挪半像素。
    public func isDragBeyondThreshold(mouse: CGPoint, threshold: CGFloat = 3) -> Bool {
        abs(mouse.x - startMouse.x) >= threshold || abs(mouse.y - startMouse.y) >= threshold
    }
}
