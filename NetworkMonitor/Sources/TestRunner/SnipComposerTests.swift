import CoreGraphics
import Foundation
import NetworkMonitorCore

// MARK: - 标注合成导出

func runSnipComposerTests() {
    print("🧪 Testing Snip annotation composer...")

    // 100×100 白底
    let size = 100
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
    var pixels = [UInt8](repeating: 255, count: size * size * 4)
    let base: CGImage? = pixels.withUnsafeMutableBytes { raw -> CGImage? in
        guard let context = CGContext(data: raw.baseAddress,
                                      width: size,
                                      height: size,
                                      bitsPerComponent: 8,
                                      bytesPerRow: size * 4,
                                      space: colorSpace,
                                      bitmapInfo: bitmapInfo) else {
            return nil
        }
        return context.makeImage()
    }
    guard let base else { return }

    // 无标注：只裁剪
    let plain = SnipAnnotationComposer.compose(base: base,
                                               cropRect: CGRect(x: 10, y: 10, width: 50, height: 50),
                                               annotations: [],
                                               selectionOrigin: CGPoint(x: 10, y: 10),
                                               scale: 1)
    assertEqual(plain?.width, 50, "裁剪后宽度")
    assertEqual(plain?.height, 50, "裁剪后高度")

    // 带标注：选区 (10,10) 起，画一个从 (20,20) 到 (30,30) 的黑矩形
    let annotation = SnipAnnotation(kind: .rectangle,
                                    start: CGPoint(x: 20, y: 20),
                                    end: CGPoint(x: 30, y: 30),
                                    style: SnipAnnotationStyle(color: .black, lineWidth: 2))
    let composed = SnipAnnotationComposer.compose(base: base,
                                                  cropRect: CGRect(x: 10, y: 10, width: 50, height: 50),
                                                  annotations: [annotation],
                                                  selectionOrigin: CGPoint(x: 10, y: 10),
                                                  scale: 1)
    assertNotNil(composed, "合成出图")
    guard let composed, let sampler = SnipPixelSampler(image: composed) else { return }
    // 标注在选区局部坐标 (10,10) 处，即合成图的左上角附近
    let borderColor = sampler.color(atPixel: CGPoint(x: 10, y: 15))
    assertNotNil(borderColor, "取到边框像素")
    if let borderColor {
        let isDark = (Int(borderColor.red) + Int(borderColor.green) + Int(borderColor.blue)) / 3 < 120
        assertEqual(isDark, true, "矩形边框被烧进合成图")
    }
    assertEqual(sampler.color(atPixel: CGPoint(x: 40, y: 40)), SnipPixelColor(red: 255, green: 255, blue: 255), "标注外保持白底")

    // 越界裁剪返回 nil
    let invalid = SnipAnnotationComposer.compose(base: base,
                                                 cropRect: CGRect(x: 90, y: 90, width: 50, height: 50),
                                                 annotations: [annotation],
                                                 selectionOrigin: .zero,
                                                 scale: 1)
    assertEqual(invalid?.width, 10, "越界裁剪被裁到图像内")
}
