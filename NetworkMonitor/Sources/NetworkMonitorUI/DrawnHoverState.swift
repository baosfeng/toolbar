import CoreGraphics

// MARK: - 悬停目标推进（纯状态机）

/// 悬停目标的推进 —— 悬停高亮在自绘视图里不再由「一个可选下标」直接改改重绘
///
/// 抽出来的理由：三处（行列表 / 系统卡 / 剪贴板卡）原来各自维护 hover 状态，
/// 每处都要自己判断「进入 / 离开 / 换目标」，换目标时还要自己决定过渡值从哪开始。
/// 目标推进收敛到这里，过渡值（`DrawnBlend`）在绘制层只做一件事：跟 `blendTarget` 走。
///
/// 本类型不持有过渡值、不碰 AppKit：越界归零（`clamp`）与离开归零（`exit`）是可断言的纯口径。
public struct DrawnHoverState: Equatable, Sendable {

    /// 一次推进带来的变化（绘制层据此决定是否重绘 / 是否重启过渡）
    public enum Change: Equatable, Sendable {
        /// 目标未变
        case none
        /// 从空白进入某个目标
        case entered(Int)
        /// 从某个目标离开（含移出视图、被 clamp 归零）
        case left(Int)
        /// 从一个目标换到另一个目标（跨越行 / 条目边界）
        case moved(from: Int, to: Int)

        /// 目标是否真的变了（= 要不要重绘）
        public var isChanged: Bool { self != .none }
    }

    /// 当前悬停目标（nil = 无）
    public private(set) var target: Int?

    public init(target: Int? = nil) {
        self.target = target
    }

    /// 是否有悬停目标
    public var isHovering: Bool { target != nil }

    /// 过渡目标值（1 = 悬停，0 = 常态），直接喂给 `DrawnBlend.animate(to:)`
    public var blendTarget: CGFloat { isHovering ? 1 : 0 }

    /// 指针移到某个目标（nil = 移到空白 / 行间空隙 / 视图之外）
    @discardableResult
    public mutating func move(to index: Int?) -> Change {
        guard index != target else { return .none }
        let previous = target
        target = index
        switch (previous, index) {
        case let (nil, .some(new)): return .entered(new)
        case let (.some(old), nil): return .left(old)
        case let (.some(old), .some(new)): return .moved(from: old, to: new)
        case (nil, nil): return .none
        }
    }

    /// 指针离开整个视图：状态归零
    @discardableResult
    public mutating func exit() -> Change {
        move(to: nil)
    }

    /// 目标集合变短（行数 / 条目数变化）：越界目标归零，其余原样保留
    @discardableResult
    public mutating func clamp(count: Int) -> Change {
        guard let target, target < 0 || target >= count else { return .none }
        return move(to: nil)
    }
}
