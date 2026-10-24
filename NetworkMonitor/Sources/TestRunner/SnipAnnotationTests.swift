import CoreGraphics
import Foundation
import NetworkMonitorCore

// MARK: - 标注模型、撤销栈与渲染

/// 造一张白底画布，回调里用左上原点坐标绘制
private func renderCanvas(size: Int, draw: (CGContext) -> Void) -> CGImage? {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
    var pixels = [UInt8](repeating: 255, count: size * size * 4)
    return pixels.withUnsafeMutableBytes { raw -> CGImage? in
        guard let context = CGContext(data: raw.baseAddress,
                                      width: size,
                                      height: size,
                                      bitsPerComponent: 8,
                                      bytesPerRow: size * 4,
                                      space: colorSpace,
                                      bitmapInfo: bitmapInfo) else {
            return nil
        }
        context.translateBy(x: 0, y: CGFloat(size))
        context.scaleBy(x: 1, y: -1)
        draw(context)
        return context.makeImage()
    }
}

private func isDark(_ color: SnipPixelColor?) -> Bool {
    guard let color else { return false }
    let luminance = (Int(color.red) + Int(color.green) + Int(color.blue)) / 3
    return luminance < 100
}

func runSnipAnnotationTests() {
    print("🧪 Testing Snip annotation model & renderer...")

    // 撤销栈
    var stack = SnipAnnotationStack()
    assertEqual(stack.isEmpty, true, "初始为空")
    let first = SnipAnnotation(kind: .rectangle, start: .zero, end: CGPoint(x: 20, y: 20))
    stack.add(first)
    assertEqual(stack.annotations.count, 1, "新增一条")
    assertEqual(stack.canUndo, true, "可撤销")
    stack.undo()
    assertEqual(stack.annotations.count, 0, "撤销后清空")
    assertEqual(stack.canRedo, true, "可重做")
    stack.redo()
    assertEqual(stack.annotations.count, 1, "重做恢复")
    stack.add(SnipAnnotation(kind: .line, start: .zero, end: CGPoint(x: 5, y: 5)))
    assertEqual(stack.canRedo, false, "新操作清空重做栈")
    stack.clear()
    assertEqual(stack.isEmpty, true, "清空后为空")
    assertEqual(stack.canRedo, false, "清空后不可重做")

    // 退化图元
    assertEqual(SnipAnnotation(kind: .rectangle, start: .zero, end: CGPoint(x: 0.5, y: 0.5)).isDegenerate(),
                true, "亚像素矩形视为误触")
    assertEqual(SnipAnnotation(kind: .rectangle, start: .zero, end: CGPoint(x: 20, y: 20)).isDegenerate(),
                false, "正常矩形不丢弃")

    // 渲染：矩形边框
    let rectangle = SnipAnnotation(kind: .rectangle,
                                   start: CGPoint(x: 20, y: 20),
                                   end: CGPoint(x: 80, y: 80),
                                   style: SnipAnnotationStyle(color: .black, lineWidth: 4))
    guard let rectImage = renderCanvas(size: 100, draw: { context in
        SnipAnnotationRenderer.draw([rectangle], in: context)
    }), let rectSampler = SnipPixelSampler(image: rectImage) else { return }
    assertEqual(isDark(rectSampler.color(atPixel: CGPoint(x: 50, y: 20))), true, "矩形上边框有墨")
    assertEqual(isDark(rectSampler.color(atPixel: CGPoint(x: 50, y: 50))), false, "矩形内部保持白底")

    // 渲染：实心矩形
    var filledStyle = SnipAnnotationStyle(color: .black, lineWidth: 2)
    filledStyle.filled = true
    let filled = SnipAnnotation(kind: .rectangle,
                                start: CGPoint(x: 20, y: 20),
                                end: CGPoint(x: 80, y: 80),
                                style: filledStyle)
    guard let filledImage = renderCanvas(size: 100, draw: { context in
        SnipAnnotationRenderer.draw([filled], in: context)
    }), let filledSampler = SnipPixelSampler(image: filledImage) else { return }
    assertEqual(isDark(filledSampler.color(atPixel: CGPoint(x: 50, y: 50))), true, "实心矩形内部被填充")

    // 渲染：箭头主线
    let arrow = SnipAnnotation(kind: .arrow,
                               start: CGPoint(x: 10, y: 50),
                               end: CGPoint(x: 90, y: 50),
                               style: SnipAnnotationStyle(color: .black, lineWidth: 3))
    guard let arrowImage = renderCanvas(size: 100, draw: { context in
        SnipAnnotationRenderer.draw([arrow], in: context)
    }), let arrowSampler = SnipPixelSampler(image: arrowImage) else { return }
    assertEqual(isDark(arrowSampler.color(atPixel: CGPoint(x: 50, y: 50))), true, "箭头主线有墨")
    assertEqual(isDark(arrowSampler.color(atPixel: CGPoint(x: 50, y: 80))), false, "箭头下方无墨")

    // 渲染：画笔折线
    let freehand = SnipAnnotation(kind: .freehand,
                                  start: CGPoint(x: 10, y: 10),
                                  end: CGPoint(x: 90, y: 10),
                                  points: [CGPoint(x: 10, y: 10), CGPoint(x: 50, y: 50), CGPoint(x: 90, y: 10)],
                                  style: SnipAnnotationStyle(color: .black, lineWidth: 3))
    guard let freehandImage = renderCanvas(size: 100, draw: { context in
        SnipAnnotationRenderer.draw([freehand], in: context)
    }), let freehandSampler = SnipPixelSampler(image: freehandImage) else { return }
    assertEqual(isDark(freehandSampler.color(atPixel: CGPoint(x: 50, y: 50))), true, "折线拐点有墨")

    // 命中判定
    let line = SnipAnnotation(kind: .line,
                              start: CGPoint(x: 0, y: 0),
                              end: CGPoint(x: 100, y: 0),
                              style: SnipAnnotationStyle(lineWidth: 2))
    assertEqual(SnipAnnotationRenderer.hitTest(line, point: CGPoint(x: 50, y: 3)), true, "线段近距离命中")
    assertEqual(SnipAnnotationRenderer.hitTest(line, point: CGPoint(x: 50, y: 30)), false, "线段远处不命中")
    assertEqual(SnipAnnotationRenderer.hitTest(rectangle, point: CGPoint(x: 50, y: 50)), true, "矩形内部命中")
    assertEqual(SnipAnnotationRenderer.hitTest(rectangle, point: CGPoint(x: 500, y: 500)), false, "矩形外部不命中")

    // 距离工具
    assertEqual(SnipAnnotationRenderer.distanceToSegment(CGPoint(x: 50, y: 10),
                                                         CGPoint(x: 0, y: 0),
                                                         CGPoint(x: 100, y: 0)), 10, "点到线段距离")
}
