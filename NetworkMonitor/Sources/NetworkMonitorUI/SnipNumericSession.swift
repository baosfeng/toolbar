import CoreGraphics
import Foundation

// MARK: - 一次截图里数值调整的会话状态

/// 覆盖层里与数值调整相关的可变状态（滚轮余量 / 放大镜倍数 / 正在输入哪个参数）
///
/// 收成一个值类型而不是三个独立属性：它们同生同灭（一次截图一份），
/// 且都不该进偏好。放在 UI target 才能被 TestRunner 直接断言复位口径。
public struct SnipNumericSession: Equatable, Sendable {

    /// 滚轮余量累加器 —— 触控板与鼠标滚轮共用的归一化（见 SnipScrollStepper）
    public var scrollStepper = SnipScrollStepper()

    /// 放大镜倍数（2–16×）；选区阶段滚轮可调
    ///
    /// 不落偏好：它是一次性的「看清这段像素」的辅助，不是用户的长期偏好。
    public var magnifierZoom: CGFloat = SnipNumericParam.magnifierZoom.defaultValue

    /// 正在输入哪个数值（nil = 没有数值输入框）
    ///
    /// 输入框本身不挂业务状态：同一个 SizeEditorField 被尺寸输入与数值输入复用，
    /// 若把参数存在 field 上，两条链路会互相污染。
    public var editingParam: SnipNumericParam?

    public init() {}

    /// 换工具 / 换参数时清掉余量，避免上一根旋钮的累计影响下一根
    public mutating func resetScroll() {
        scrollStepper.reset()
    }
}
