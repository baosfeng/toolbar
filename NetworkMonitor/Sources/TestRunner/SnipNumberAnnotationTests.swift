import CoreGraphics
import Foundation
import NetworkMonitorCore

// MARK: - 序号标注（工具 / 编号递增 / 几何 / 渲染命中）

func runSnipNumberAnnotationTests() {
    print("🧪 Testing snip number annotation...")

    assertEqual(SnipTool.number.annotationKind, SnipAnnotationKind.number, "序号工具对应 number 图元")
    assertEqual(SnipTool.number.displayName, "序号", "序号工具显示名")
    assertEqual(SnipTool.number.isActionTool, false, "序号不是动作工具")
    assertEqual(SnipTool.eraser.isActionTool, true, "橡皮擦是动作工具")
    assertEqual(SnipAnnotationKind.number.displayName, "序号", "序号图元显示名")
    assertEqual(SnipAnnotationKind.number.isDrawable, false, "序号是单击落点，不拖拽绘制")
    assertEqual(SnipAnnotationKind.number.needsBaseImage, false, "序号不需要底图像素")

    // 编号递增：空列表从 1 开始；取最大值 + 1（删掉中间项不重排）
    assertEqual(SnipNumberSequence.next(after: []), 1, "空列表第一个序号是 1")
    assertEqual(SnipNumberSequence.next(after: [1]), 2, "单个序号递增到 2")
    assertEqual(SnipNumberSequence.next(after: [1, 2, 3]), 4, "顺序递增")
    assertEqual(SnipNumberSequence.next(after: [1, 5, 3]), 6, "删掉中间项后不重排，取最大 + 1")
    assertEqual(SnipNumberSequence.next(after: [0, -2]), 1, "非正数与空等价")

    // 从标注里取序号值：只认 number 图元，坏文本忽略
    let number = SnipAnnotation(kind: .number,
                                start: CGPoint(x: 0, y: 0),
                                end: CGPoint(x: 40, y: 40),
                                text: "7")
    let rect = SnipAnnotation(kind: .rectangle,
                              start: CGPoint(x: 0, y: 0),
                              end: CGPoint(x: 10, y: 10),
                              text: "9")
    let broken = SnipAnnotation(kind: .number,
                                start: CGPoint(x: 0, y: 0),
                                end: CGPoint(x: 40, y: 40),
                                text: "abc")
    assertEqual(SnipNumberSequence.values(in: [number, rect, broken]), [7], "只取序号图元的合法数字")
    assertEqual(SnipNumberSequence.next(after: SnipNumberSequence.values(in: [number, broken])), 8,
                "跳过坏文本后仍按 7 递增")

    // 几何：半径随线宽变粗，但不小于 14pt；外接框以点击点为圆心
    assertEqual(SnipNumberAnnotation.radius(forLineWidth: 2), 14, "细线宽时半径取下限 14")
    assertEqual(SnipNumberAnnotation.radius(forLineWidth: 8), 32, "粗线宽时半径 = 4 倍线宽")
    let bounds = SnipNumberAnnotation.boundingRect(center: CGPoint(x: 100, y: 50), lineWidth: 3)
    assertEqual(bounds.midX, 100, "外接框水平居中于点击点")
    assertEqual(bounds.midY, 50, "外接框垂直居中于点击点")
    assertEqual(bounds.width, SnipNumberAnnotation.radius(forLineWidth: 3) * 2, "外接框宽 = 直径")

    // 命中：点在圆内算命中，圆外的外接框角上不算（序号按整圆命中）
    assertEqual(SnipAnnotationRenderer.hitTest(number, point: CGPoint(x: 20, y: 20)), true,
                "圆心命中")
    assertEqual(SnipAnnotationRenderer.hitTest(number, point: CGPoint(x: 38, y: 3), tolerance: 0), false,
                "外接框角上（圆外）不命中")

    // 退化判据：序号的外接框天然 > 2pt，不会被当成误触丢弃
    assertEqual(number.isDegenerate(), false, "序号不会被判为误触")

    print("✅ 序号标注测试通过")
}
