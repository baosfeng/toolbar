import CoreGraphics
import Foundation

// MARK: - 序号标注

/// 序号标注的几何与编号口径 —— 纯函数，渲染 / 交互 / 测试共用
///
/// 口径（与 sniplite 一致）：点一下落一个圆底数字，编号在落笔时定死、不随删除重排
/// （删掉中间的 2 之后，新序号仍取当前最大号 + 1，避免已有图上的 1/2/3 被改名）。
public enum SnipNumberAnnotation {

    /// 圆的半径 —— 由线宽推出来，保证粗笔画的序号不会比线还细
    public static func radius(forLineWidth lineWidth: CGFloat) -> CGFloat {
        max(lineWidth * 4, 14)
    }

    /// 序号在页面里的外接框（点 = 圆心）
    public static func boundingRect(center: CGPoint, lineWidth: CGFloat) -> CGRect {
        let radius = radius(forLineWidth: lineWidth)
        return CGRect(x: center.x - radius,
                      y: center.y - radius,
                      width: radius * 2,
                      height: radius * 2)
    }
}

// MARK: - 编号递增

/// 序号递增规则：取已有序号的最大值 + 1，空列表从 1 开始
public enum SnipNumberSequence {

    /// 下一个序号
    /// - Parameter existing: 已落笔的序号值（非数字或空串忽略）
    public static func next(after existing: [Int]) -> Int {
        let valid = existing.filter { $0 > 0 }
        return (valid.max() ?? 0) + 1
    }

    /// 从标注的 text 字段里取出序号值（非序号图元返回 nil）
    public static func values(in annotations: [SnipAnnotation]) -> [Int] {
        annotations.compactMap { annotation in
            guard annotation.kind == .number else { return nil }
            return Int(annotation.text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
