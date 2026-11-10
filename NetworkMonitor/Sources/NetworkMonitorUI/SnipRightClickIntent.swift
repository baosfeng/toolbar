import Foundation

// MARK: - 右键语义（纯逻辑，可单测）

/// 截图覆盖层上一次右键 / 一次「结束编辑」该做什么
///
/// Snipaste 两张键位表对右键给了不同含义：「只对截图有效」表里右键 = 重新设置截屏区域 / 中止截屏，
/// 「通用」表里右键 = 结束对当前标注的编辑（常见问题也写明「标注文字时右键点一下即可结束输入」）。
/// 早期实现一律当成中止，画到一半按右键会把整张截图连同已有标注一起丢掉。
/// 判定收进这里的纯函数，界面层只负责按结果执行。
public enum SnipRightClickIntent {

    /// 一次右键的落点
    public enum Outcome: Equatable {
        /// 只收笔：结束当前标注的编辑，截图与已完成的标注都保留
        case finishAnnotation
        /// 中止整次截图
        case cancelSnip
    }

    /// 判定一次右键
    ///
    /// - Parameters:
    ///   - hasDraft: 是否正在拖拽画一个尚未提交的图形
    ///   - isTextEditing: 文字输入框是否正在编辑
    ///   - hasSelectedAnnotation: 是否有已选中待二次操作（改字号 / 旋转）的标注
    public static func outcome(hasDraft: Bool,
                               isTextEditing: Bool,
                               hasSelectedAnnotation: Bool) -> Outcome {
        if hasDraft || isTextEditing || hasSelectedAnnotation {
            return .finishAnnotation
        }
        return .cancelSnip
    }
}
