import CoreGraphics
import Foundation

// MARK: - 已绘图形的整体缩放（⇧ + 滚轮）

/// 把一条已绘标注按比例从中心缩放 —— Snipaste v2.11「Shift + 滚轮缩放选中的矩形/椭圆」
///
/// 只缩放几何（start / end / points），不动样式与文字内容：字号缩放是另一根旋钮（fontScale），
/// 两者叠在一起会让「调大一点」变成「又变大又变粗」，用户再也退不回原样。
///
/// 缩放下限按最短边 2pt 卡住：再小就点不中、也看不见，等于删掉了一条标注却还能撤销回来。
public enum SnipAnnotationScaler {

    /// 单次滚轮对应的缩放比例
    ///
    /// 8% 一档：从 100% 到 200% 约 9 格，与「滚轮调线宽」的手感同一量级。
    public static let stepRatio: CGFloat = 0.08

    /// 最小边长（点）
    public static let minimumSide: CGFloat = 2

    /// 最大放大倍数（相对原始尺寸）—— 防止滚过头把图形撑到屏幕外找不回来
    public static let maximumScale: CGFloat = 20

    /// 按「滚了几格」缩放一条标注；返回新标注与是否真的变了
    ///
    /// - Parameters:
    ///   - annotation: 原标注
    ///   - steps: 正 = 放大，负 = 缩小
    public static func scaled(_ annotation: SnipAnnotation, steps: Int) -> (annotation: SnipAnnotation, changed: Bool) {
        guard steps != 0 else { return (annotation, false) }
        let rect = annotation.boundingRect
        // 文字与序号没有可缩放的最小包围盒意义（文字该改字号、序号该改半径），
        // 这里只对「有包围盒的图形」生效，其余原样返回
        guard rect.width > 0, rect.height > 0, !annotation.kind.isStroke else {
            return (annotation, false)
        }
        let factor = 1 + CGFloat(steps) * stepRatio
        // 缩小时别把 factor 变成 0 或负数：一格最多缩 8%，连滚多格时按最小边长兜底
        let safeFactor = max(factor, 0.2)
        let next = resized(annotation, factor: safeFactor)
        let nextRect = next.boundingRect
        guard nextRect.width >= minimumSide, nextRect.height >= minimumSide else {
            return (annotation, false)
        }
        // 上限：缩放后的包围盒不应超过原尺寸的 maximumScale 倍
        let ratio = min(nextRect.width / rect.width, nextRect.height / rect.height)
        guard ratio <= maximumScale else { return (annotation, false) }
        return (next, true)
    }

    /// 以包围盒中心为锚做等比缩放
    ///
    /// 锚点取中心而不是左上角：用户选中一条箭头后按 ⇧ 滚轮，直觉是「它原地变大」，
    /// 若以左上角为锚，图形会一边变大一边往右下跑。
    public static func resized(_ annotation: SnipAnnotation, factor: CGFloat) -> SnipAnnotation {
        guard factor > 0, factor != 1 else { return annotation }
        let center = CGPoint(x: annotation.boundingRect.midX, y: annotation.boundingRect.midY)
        var result = annotation
        result.start = scaled(annotation.start, around: center, factor: factor)
        result.end = scaled(annotation.end, around: center, factor: factor)
        result.points = annotation.points.map { scaled($0, around: center, factor: factor) }
        return result
    }

    private static func scaled(_ point: CGPoint, around center: CGPoint, factor: CGFloat) -> CGPoint {
        CGPoint(x: center.x + (point.x - center.x) * factor,
                y: center.y + (point.y - center.y) * factor)
    }
}
