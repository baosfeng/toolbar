import Foundation

// MARK: - 贴图窗鼠标按键语义（纯逻辑，可单测）

/// 贴图窗上一次鼠标按下该做什么

/// 官方贴图行为里「左键双击关闭」「中键单击重置为 100% 大小与 100% 不透明」，
/// 而左键单击与按住拖动都要移动窗口：双击与中键必须先判出来，
/// 否则一次双击会被拖动吃掉、永远落不到关闭上。判定收进这里的纯函数，内容视图只按结果执行。
///
/// 右键不归这里判：它要弹出上下文菜单，必须原样交给 AppKit 的默认处理，
/// 否则右键会被当成拖动把手（窗口跟着鼠标跑、菜单永远弹不出来）。
public enum PinClickIntent {

    /// 一次按下的落点
    public enum Outcome: Equatable {
        /// 关闭贴图（可恢复）
        case closeWindow
        /// 重置为 100% 大小与 100% 不透明
        case resetSizeAndAlpha
        /// 移动窗口（左键单击与按住拖动都走这条）
        case dragWindow
        /// 不归贴图窗判定：交给 AppKit 默认处理（右键菜单、其他侧键）
        case passThrough
    }

    /// 判定一次鼠标按下
    ///
    /// - Parameters:
    ///   - buttonNumber: 0 = 左键，1 = 右键，2 = 中键（NSEvent.buttonNumber 口径）
    ///   - clickCount: 连击计数，≥ 2 即双击
    public static func outcome(buttonNumber: Int, clickCount: Int) -> Outcome {
        switch buttonNumber {
        case 0: return clickCount >= 2 ? .closeWindow : .dragWindow
        case 2: return .resetSizeAndAlpha
        default: return .passThrough
        }
    }
}
