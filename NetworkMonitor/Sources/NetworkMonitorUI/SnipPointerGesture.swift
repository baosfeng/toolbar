import CoreGraphics
import Foundation

// MARK: - 截图鼠标手势判定（纯逻辑，可单测）

/// 覆盖层上「一次按下 → 拖拽 → 松手」该被判成什么
///
/// 早期实现在 hover 到窗口时于 mouseDown 里立刻成立整窗选区，用户想拖任意区域时
/// 鼠标一按下就被判成「点选窗口」，于是只能整窗截图、画不出自定义选区。
/// 这里把判定抽成纯函数：位移小于阈值算单击选窗，超过则算自定义选区。
public enum SnipPointerGesture {

    /// 判定结果
    public enum Outcome: Equatable {
        /// 生成自定义选区（拖拽）
        case dragSelection
        /// 点选整窗（单击且按下时悬停在某个窗口）
        case clickWindow
    }

    /// 单击与拖拽的判定阈值（点）：4 点足以吃掉触控板抖动，又远小于真实拖拽位移
    public static let clickTolerance: CGFloat = 4

    /// 判定一次鼠标手势
    ///
    /// - Parameters:
    ///   - start: 按下落点
    ///   - end: 松手落点
    ///   - hasHoveredWindow: 按下时是否悬停在某个窗口
    public static func outcome(start: CGPoint, end: CGPoint, hasHoveredWindow: Bool) -> Outcome {
        guard hasHoveredWindow else { return .dragSelection }
        let dx = end.x - start.x
        let dy = end.y - start.y
        let distance = (dx * dx + dy * dy).squareRoot()
        return distance <= clickTolerance ? .clickWindow : .dragSelection
    }
}
