import CoreGraphics
import Foundation
import NetworkMonitorCore

// MARK: - 文字标注

private func makeWhiteCanvas(size: Int, draw: (CGContext) -> Void) -> CGImage? {
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

func runSnipTextTests() {
    print("🧪 Testing Snip text annotation...")

    // 尺寸测量
    let size = SnipAnnotationRenderer.textSize("测试ABC", fontSize: 18)
    assertEqual(size.width > 0, true, "文字宽度大于 0")
    assertEqual(size.height > 10, true, "文字高度合理")

    // 空文字视为退化
    let empty = SnipAnnotation(kind: .text, start: .zero, end: .zero, text: "   ")
    assertEqual(empty.isDegenerate(), true, "空白文字被丢弃")
    let normal = SnipAnnotation(kind: .text, start: .zero, end: .zero, text: "Hi")
    assertEqual(normal.isDegenerate(), false, "有内容不丢弃")

    // 字号随线宽联动
    var style = SnipAnnotationStyle(color: .black, lineWidth: 2)
    style.lineWidth = 2
    let small = SnipAnnotation(kind: .text, start: .zero, end: .zero, text: "A", style: style)
    style.lineWidth = 8
    let large = SnipAnnotation(kind: .text, start: .zero, end: .zero, text: "A", style: style)
    assertEqual(large.fontSize > small.fontSize, true, "线宽越大字号越大")

    // 渲染：白底画黑字，文字区域应有墨
    let text = SnipAnnotation(kind: .text,
                              start: CGPoint(x: 10, y: 10),
                              end: .zero,
                              text: "HI",
                              style: SnipAnnotationStyle(color: .black, lineWidth: 4))
    guard let image = makeWhiteCanvas(size: 100, draw: { context in
        SnipAnnotationRenderer.draw([text], in: context)
    }), let sampler = SnipPixelSampler(image: image) else { return }

    var darkPixels = 0
    for x in 8..<60 {
        for y in 8..<40 {
            if let color = sampler.color(atPixel: CGPoint(x: x, y: y)) {
                let average = (Int(color.red) + Int(color.green) + Int(color.blue)) / 3
                if average < 128 { darkPixels += 1 }
            }
        }
    }
    assertEqual(darkPixels > 20, true, "文字被渲染出墨点")

    // 命中测试：文字框内命中，远处不命中
    assertEqual(SnipAnnotationRenderer.hitTest(text, point: CGPoint(x: 15, y: 20)), true, "文字框内命中")
    assertEqual(SnipAnnotationRenderer.hitTest(text, point: CGPoint(x: 90, y: 90)), false, "文字框外不命中")

    // 字号缩放
    var scaled = SnipAnnotation(kind: .text,
                                start: .zero,
                                end: .zero,
                                text: "A",
                                style: SnipAnnotationStyle(lineWidth: 4))
    let baseFontSize = scaled.fontSize
    scaled.fontScale = 2
    assertEqual(scaled.fontSize, baseFontSize * 2, "字号随缩放倍数翻倍")

    // 旋转后仍能渲染出墨
    var rotated = SnipAnnotation(kind: .text,
                                 start: CGPoint(x: 30, y: 30),
                                 end: .zero,
                                 text: "HI",
                                 style: SnipAnnotationStyle(color: .black, lineWidth: 4))
    rotated.rotation = .pi / 4
    guard let rotatedImage = makeWhiteCanvas(size: 100, draw: { context in
        SnipAnnotationRenderer.draw([rotated], in: context)
    }), let rotatedSampler = SnipPixelSampler(image: rotatedImage) else { return }
    var rotatedDark = 0
    for x in 20..<90 {
        for y in 20..<90 {
            if let color = rotatedSampler.color(atPixel: CGPoint(x: x, y: y)),
               (Int(color.red) + Int(color.green) + Int(color.blue)) / 3 < 128 {
                rotatedDark += 1
            }
        }
    }
    assertEqual(rotatedDark > 10, true, "旋转后的文字仍被渲染")

    // 局部擦除：最近点定位
    let trail = [CGPoint(x: 0, y: 0), CGPoint(x: 20, y: 20), CGPoint(x: 40, y: 0)]
    assertEqual(SnipAnnotationRenderer.nearestPointIndex(in: trail, to: CGPoint(x: 21, y: 19), tolerance: 5),
                1, "命中轨迹中间点")
    assertEqual(SnipAnnotationRenderer.nearestPointIndex(in: trail, to: CGPoint(x: 200, y: 200), tolerance: 5) == nil,
                true, "远处不命中轨迹")

    // 局部擦除：替换后点数减少
    var erasureStack = SnipAnnotationStack()
    var trailAnnotation = SnipAnnotation(kind: .polyline,
                                         start: CGPoint(x: 0, y: 0),
                                         end: CGPoint(x: 40, y: 0),
                                         points: trail)
    erasureStack.add(trailAnnotation)
    trailAnnotation.points.removeSubrange(0..<2)
    trailAnnotation.start = trailAnnotation.points[0]
    erasureStack.replace(at: 0, with: trailAnnotation)
    assertEqual(erasureStack.annotations[0].points.count, 1, "局部擦除后轨迹点减少")
    assertEqual(erasureStack.annotations[0].start, CGPoint(x: 40, y: 0), "起点跟随剩余轨迹")
}
