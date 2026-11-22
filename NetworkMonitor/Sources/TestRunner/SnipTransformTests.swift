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

/// 半透明红（直通 255,0,0,128 → 预乘 128,0,0,128），用来验 alpha 不会被滤镜改掉
private func makeTranslucentImage() -> CGImage? {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
    let pixels: [UInt8] = [128, 0, 0, 128]
    return CGDataProvider(data: Data(pixels) as CFData).flatMap { provider in
        CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: 4, space: colorSpace,
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
    // MARK: 灰度（Rec.601 加权）与反色

    // 2×2 已知像素：红 / 绿 / 蓝 / 白（全不透明）
    guard let gray = SnipImageTransform.grayscale(source),
          let graySampler = SnipPixelSampler(image: gray) else { return }
    assertEqual(gray.width, 2, "灰度不改变宽度")
    assertEqual(gray.height, 2, "灰度不改变高度")
    // Y = 0.299R + 0.587G + 0.114B（四舍五入）：红 76、绿 150、蓝 29、白 255
    assertEqual(graySampler.color(atPixel: CGPoint(x: 0, y: 0)),
                SnipPixelColor(red: 76, green: 76, blue: 76), "灰度：纯红 → 76")
    assertEqual(graySampler.color(atPixel: CGPoint(x: 1, y: 0)),
                SnipPixelColor(red: 150, green: 150, blue: 150), "灰度：纯绿 → 150")
    assertEqual(graySampler.color(atPixel: CGPoint(x: 0, y: 1)),
                SnipPixelColor(red: 29, green: 29, blue: 29), "灰度：纯蓝 → 29")
    assertEqual(graySampler.color(atPixel: CGPoint(x: 1, y: 1)),
                SnipPixelColor(red: 255, green: 255, blue: 255), "灰度：白仍是白")
    // 灰度是可重复的：对灰度图再灰度一次结果不变（幂等）
    guard let gray2 = SnipImageTransform.grayscale(gray),
          let gray2Sampler = SnipPixelSampler(image: gray2) else { return }
    assertEqual(gray2Sampler.color(atPixel: CGPoint(x: 1, y: 0)),
                graySampler.color(atPixel: CGPoint(x: 1, y: 0)), "灰度幂等：再灰度一次不变")

    guard let inverted = SnipImageTransform.inverted(source),
          let invertedSampler = SnipPixelSampler(image: inverted) else { return }
    assertEqual(inverted.width, 2, "反色不改变宽度")
    assertEqual(invertedSampler.color(atPixel: CGPoint(x: 0, y: 0)),
                SnipPixelColor(red: 0, green: 255, blue: 255), "反色：红 → 青")
    assertEqual(invertedSampler.color(atPixel: CGPoint(x: 1, y: 0)),
                SnipPixelColor(red: 255, green: 0, blue: 255), "反色：绿 → 洋红")
    assertEqual(invertedSampler.color(atPixel: CGPoint(x: 0, y: 1)),
                SnipPixelColor(red: 255, green: 255, blue: 0), "反色：蓝 → 黄")
    assertEqual(invertedSampler.color(atPixel: CGPoint(x: 1, y: 1)),
                SnipPixelColor(red: 0, green: 0, blue: 0), "反色：白 → 黑")
    // 反色是对合运算：连续两次回到原图
    guard let invertedTwice = SnipImageTransform.inverted(inverted),
          let invertedTwiceSampler = SnipPixelSampler(image: invertedTwice) else { return }
    assertEqual(invertedTwiceSampler.color(atPixel: CGPoint(x: 0, y: 0)),
                sourceSampler.color(atPixel: CGPoint(x: 0, y: 0)), "反色两次回到原图")

    // MARK: 半透明像素：alpha 原样保留，RGB 按预乘口径换算

    // 半透明红：直通 (255,0,0,128) 预乘后为 (128,0,0,128)；灰度 Y=76 → 预乘 38
    guard let translucent = makeTranslucentImage() else { return }
    guard let translucentGray = SnipImageTransform.grayscale(translucent),
          let translucentGraySampler = SnipPixelSampler(image: translucentGray) else { return }
    assertEqual(translucentGraySampler.color(atPixel: CGPoint(x: 0, y: 0)),
                SnipPixelColor(red: 38, green: 38, blue: 38),
                "灰度：半透明红按直通值算 Y 再预乘回 alpha（38 = 76 × 128/255）")
    guard let translucentInverted = SnipImageTransform.inverted(translucent),
          let translucentInvertedSampler = SnipPixelSampler(image: translucentInverted) else { return }
    assertEqual(translucentInvertedSampler.color(atPixel: CGPoint(x: 0, y: 0)),
                SnipPixelColor(red: 0, green: 128, blue: 128),
                "反色：半透明红 → 预乘后的青（alpha − 通道值，alpha 仍为 128）")
}

