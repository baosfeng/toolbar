import CoreGraphics

// MARK: - 区域命中（纯口径）

/// 区域命中的纯函数 —— 自绘视图没有子视图可分配事件，命中一律现算
///
/// 面板里的命中只有两种形态，抽在这一处，绘制层与业务视图都调它：
/// - **等步行带**（行列表、图表柱子）：行高 + 行距，点在行间空隙不算命中；
/// - **优先级查表**（卡头按钮压在整卡上、角标压在正文上）：按给定顺序取第一个包含点的区域。
///
/// 坐标系一律为自绘视图的翻转坐标（y 向下），与 `ClipboardCardGeometry` 同一口径。
public enum DrawnHitRegions {

    /// 等步行带命中：点在带内（含带的下边缘）命中，落在带间空隙返回 nil
    ///
    /// - Parameters:
    ///   - point: 视图坐标（y 向下）
    ///   - bandHeight: 单条带高度（= 行高）
    ///   - step: 条带步进（= 行高 + 行距），必须 > 0
    ///   - count: 条带数量
    /// - Returns: 命中的下标；越界 / 落在空隙 / 点在视图上方时为 nil
    public static func bandIndex(at point: CGPoint,
                                 bandHeight: CGFloat,
                                 step: CGFloat,
                                 count: Int) -> Int? {
        guard count > 0, step > 0, point.y >= 0 else { return nil }
        let index = Int((point.y / step).rounded(.down))
        guard index >= 0, index < count else { return nil }
        return point.y - CGFloat(index) * step <= bandHeight ? index : nil
    }

    /// 按给定顺序取第一个包含点的区域（数组顺序即优先级，靠前的先命中）
    ///
    /// 空矩形（宽或高为 0）不参与命中：面板里「没有角标 / 没有卡头按钮」时矩形就是 `.zero`。
    public static func priorityIndex(at point: CGPoint, in rects: [CGRect]) -> Int? {
        for (index, rect) in rects.enumerated() where rect.width > 0 && rect.height > 0 {
            if rect.contains(point) { return index }
        }
        return nil
    }

    /// 单矩形命中（整卡 / 星标这类单一目标；空矩形一律不命中）
    public static func contains(_ point: CGPoint, in rect: CGRect) -> Bool {
        rect.width > 0 && rect.height > 0 && rect.contains(point)
    }
}
