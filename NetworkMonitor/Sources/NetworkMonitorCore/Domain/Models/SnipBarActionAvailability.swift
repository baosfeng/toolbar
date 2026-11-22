// MARK: - 工具条动作可用性（纯逻辑，可单测）

/// 工具条输出动作的可用性快照 —— 由覆盖层按标注栈灌进工具条，视图只读、不问 Core
///
/// 为什么是「灌进来的值」而不是让视图去问栈：工具条是纯视图，栈归覆盖层所有；
/// 视图自己取全局状态就会出现「栈变了、条上还亮着」的滞后与不可测。
/// 撤销 / 重做是唯一有可用性维度的动作：栈空时置灰且不响应点击，
/// 其余四个动作（取消 / 复制 / 保存 / 贴图）恒可用。
public struct SnipBarActionAvailability: Equatable, Sendable {

    /// 还能撤销（标注栈里还有图元）
    public let canUndo: Bool
    /// 还能重做（重做栈里还有刚撤掉的一条）
    public let canRedo: Bool

    public init(canUndo: Bool, canRedo: Bool) {
        self.canUndo = canUndo
        self.canRedo = canRedo
    }

    /// 栈空态：两个都不可用（工具条初始值与「全清空」后的状态）
    public static let unavailable = SnipBarActionAvailability(canUndo: false, canRedo: false)

    /// 该动作此刻能不能点
    ///
    /// 只有撤销 / 重做会随栈变化；其余动作恒可用，避免「工具条上有个永远点不动的按钮」。
    public func isEnabled(_ action: SnipBarAction) -> Bool {
        switch action {
        case .undo: return canUndo
        case .redo: return canRedo
        case .cancel, .copy, .save, .pin: return true
        }
    }
}