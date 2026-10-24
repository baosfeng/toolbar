import CoreGraphics
import Foundation
import NetworkMonitorCore

// MARK: - 贴图旋转与镜像

private func makeQuadrantImage() -> CGImage? {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
    // 顶行：左红 右绿；底行：左蓝 右白
    let pixels: [UInt8] = [
        255, 0, 0, 255,     0, 255, 0, 255,
        0, 0, 255, 255,     255, 255, 255, 255
    ]
    return CGDataProvider(data: Data(pixels) as CFData).flatMap { provider in
        CGImage(width: 2, height: 2, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: 8, space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
                provider: provider, decode: nil, shouldInterpolate: false,
                intent: .defaultIntent)
    }
}

func runSnipTransformTests() {
    print("🧪 Testing Snip image transform...")
    guard let source = makeQuadrantImage(),
          let sourceSampler = SnipPixelSampler(image: source) else { return }
    let red = SnipPixelColor(red: 255, green: 0, blue: 0)
    let green = SnipPixelColor(red: 0, green: 255, blue: 0)
    let blue = SnipPixelColor(red: 0, green: 0, blue: 255)
    let white = SnipPixelColor(red: 255, green: 255, blue: 255)
    assertEqual(sourceSampler.color(atPixel: CGPoint(x: 0, y: 0)), red, "原图左上为红")

    // 顺时针 90°：左上变蓝、右上变红、右下变绿、左下变白
    guard let rotated = SnipImageTransform.rotated(source, clockwise: true),
          let rotatedSampler = SnipPixelSampler(image: rotated) else { return }
    assertEqual(rotated.width, 2, "旋转后宽度等于原高度")
    assertEqual(rotated.height, 2, "旋转后高度等于原宽度")
    assertEqual(rotatedSampler.color(atPixel: CGPoint(x: 0, y: 0)), blue, "顺时针：左上为原左下")
    assertEqual(rotatedSampler.color(atPixel: CGPoint(x: 1, y: 0)), red, "顺时针：右上为原左上")
    assertEqual(rotatedSampler.color(atPixel: CGPoint(x: 1, y: 1)), green, "顺时针：右下为原右上")
    assertEqual(rotatedSampler.color(atPixel: CGPoint(x: 0, y: 1)), white, "顺时针：左下为原右下")

    // 水平镜像：左右互换
    guard let mirroredH = SnipImageTransform.mirrored(source, horizontal: true),
          let mirroredHSampler = SnipPixelSampler(image: mirroredH) else { return }
    assertEqual(mirroredHSampler.color(atPixel: CGPoint(x: 0, y: 0)), green, "水平镜像：左上变原右上")
    assertEqual(mirroredHSampler.color(atPixel: CGPoint(x: 1, y: 0)), red, "水平镜像：右上变原左上")

    // 垂直镜像：上下互换
    guard let mirroredV = SnipImageTransform.mirrored(source, horizontal: false),
          let mirroredVSampler = SnipPixelSampler(image: mirroredV) else { return }
    assertEqual(mirroredVSampler.color(atPixel: CGPoint(x: 0, y: 0)), blue, "垂直镜像：左上变原左下")
    assertEqual(mirroredVSampler.color(atPixel: CGPoint(x: 0, y: 1)), red, "垂直镜像：左下变原左上")
}
