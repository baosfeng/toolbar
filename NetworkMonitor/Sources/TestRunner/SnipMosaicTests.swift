import CoreGraphics
import Foundation
import NetworkMonitorCore

// MARK: - 马赛克与模糊

/// 造一张 2 像素宽黑白交替的条纹图
private func makeStripedImage(size: Int) -> CGImage? {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
    var pixels = [UInt8](repeating: 255, count: size * size * 4)
    for y in 0..<size {
        for x in 0..<size {
            let offset = (y * size + x) * 4
            let dark = (x / 2) % 2 == 0
            let value: UInt8 = dark ? 0 : 255
            pixels[offset] = value
            pixels[offset + 1] = value
            pixels[offset + 2] = value
            pixels[offset + 3] = 255
        }
    }
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
        return context.makeImage()
    }
}

func runSnipMosaicTests() {
    print("🧪 Testing Snip mosaic & blur...")

    guard let striped = makeStripedImage(size: 100) else { return }

    // 像素化：输出尺寸 = 区域 / 块大小
    let pixelRect = CGRect(x: 0, y: 0, width: 100, height: 100)
    guard let small = SnipMosaicProcessor.pixelated(striped, in: pixelRect, blockSize: 10) else { return }
    assertEqual(small.width, 10, "像素化列数")
    assertEqual(small.height, 10, "像素化行数")

    // 模糊：尺寸不变
    guard let blurred = SnipMosaicProcessor.blurred(striped, in: pixelRect, radius: 6) else { return }
    assertEqual(blurred.width, 100, "模糊后宽度不变")
    assertEqual(blurred.height, 100, "模糊后高度不变")

    // 局部区域像素化也要有输出
    let localPixelated = SnipMosaicProcessor.pixelated(striped,
                                                       in: CGRect(x: 20, y: 20, width: 60, height: 60),
                                                       blockSize: 10)
    assertNotNil(localPixelated, "局部区域像素化非空")
    assertEqual(localPixelated?.width, 6, "局部像素化列数")

    // 合成器：马赛克块内颜色被统一（原来条纹黑白交替，块内应接近灰）
    let annotation = SnipAnnotation(kind: .mosaic,
                                    start: CGPoint(x: 20, y: 20),
                                    end: CGPoint(x: 80, y: 80),
                                    style: SnipAnnotationStyle())
    let canvas: CGImage? = {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        var pixels = [UInt8](repeating: 255, count: 100 * 100 * 4)
        return pixels.withUnsafeMutableBytes { raw -> CGImage? in
            guard let context = CGContext(data: raw.baseAddress,
                                          width: 100,
                                          height: 100,
                                          bitsPerComponent: 8,
                                          bytesPerRow: 100 * 4,
                                          space: colorSpace,
                                          bitmapInfo: bitmapInfo) else {
                return nil
            }
            context.translateBy(x: 0, y: 100)
            context.scaleBy(x: 1, y: -1)
            SnipAnnotationCompositor.draw(annotations: [annotation],
                                          base: striped,
                                          baseOrigin: .zero,
                                          scale: 1,
                                          in: context)
            return context.makeImage()
        }
    }()
    guard let canvas, let sampler = SnipPixelSampler(image: canvas) else { return }
    let left = sampler.color(atPixel: CGPoint(x: 24, y: 24))
    let right = sampler.color(atPixel: CGPoint(x: 30, y: 24))
    assertNotNil(left, "取到马赛克块左侧像素")
    assertNotNil(right, "取到马赛克块右侧像素")
    if let left, let right {
        assertEqual(left, right, "同一马赛克块内颜色一致")
        let average = (Int(left.red) + Int(left.green) + Int(left.blue)) / 3
        assertEqual(average > 20 && average < 240, true, "马赛克块取到平均值而非纯黑或纯白")
    }

    // 区域外保持白底
    assertEqual(sampler.color(atPixel: CGPoint(x: 90, y: 90)),
                SnipPixelColor(red: 255, green: 255, blue: 255), "马赛克区域外不受影响")
}
