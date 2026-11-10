import Foundation

// MARK: - 贴图窗鼠标单击语义（纯逻辑，可单测）

/// 贴图窗上一次鼠标按下该做什么
///
/// 官方贴图行为里「左键双击关闭」「中键单击重置为 100% 大小与 100% 不透明」，
/// 而窗口开着 isMovableByWindowBackground：单击与拖动要被拖动吃掉，
/// 双击与中键必须先判出来。判定收进这里的纯函数，内容视图只按结果执行。
public enum PinClickIntent {

    /// 一次按下的落点
    public enum Outcome: Equatable {
        /// 关闭贴图（可恢复）
        case closeWindow
        /// 重置为 100% 大小与 100% 不透明
        case resetSizeAndAlpha
        /// 交给窗口自己处理（单击与拖动都走这条，保留「按住任意位置拖窗」的手感）
        case dragWindow
    }

    /// 判定一次鼠标按下
    ///
    /// - Parameters:
    ///   - buttonNumber: 0 = 左键，2 = 中键（NSEvent.buttonNumber 口径）
    ///   - clickCount: 连击计数，≥ 2 即双击
    public static func outcome(buttonNumber: Int, clickCount: Int) -> Outcome {
        if buttonNumber == 2 { return .resetSizeAndAlpha }
        guard buttonNumber == 0 else { return .dragWindow }
        return clickCount >= 2 ? .closeWindow : .dragWindow
    }
}
