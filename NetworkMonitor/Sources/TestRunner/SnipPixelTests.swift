import CoreGraphics
import Foundation
import NetworkMonitorCore

// MARK: - 像素采样与取色格式

func runSnipPixelTests() {
    print("🧪 Testing Snip pixel sampler & color format...")

    let red = SnipPixelColor(red: 255, green: 0, blue: 0)
    assertEqual(red.hexString, "#FF0000", "hex 格式")
    assertEqual(red.rgbString, "RGB(255, 0, 0)", "rgb 格式")
    assertEqual(SnipPixelColor(red: 0, green: 136, blue: 255).hexString, "#0088FF", "hex 补零")
    assertEqual(SnipPixelColor.DisplayFormat.hex.text(for: red), "#FF0000", "格式枚举 hex")
    assertEqual(SnipPixelColor.DisplayFormat.rgb.text(for: red), "RGB(255, 0, 0)", "格式枚举 rgb")

    // 造一张 2x2 图：左上红、右上绿、左下蓝、右下白
    // 直接给字节，避免用 CGContext 绘制时 sRGB → deviceRGB 的色彩转换把纯色弄脏
    let width = 2, height = 2
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let rawPixels: [UInt8] = [
        255, 0, 0, 255,     0, 255, 0, 255,        // 顶行：左红 右绿
        0, 0, 255, 255,     255, 255, 255, 255    // 底行：左蓝 右白
    ]
    let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
    let image: CGImage? = CGDataProvider(data: Data(rawPixels) as CFData).flatMap { provider in
        CGImage(width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent)
    }
    assertNotNil(image, "构造 2x2 测试图")
    guard let image, let sampler = SnipPixelSampler(image: image) else { return }
    assertEqual(sampler.width, 2, "采样器宽度")
    assertEqual(sampler.height, 2, "采样器高度")
    assertEqual(sampler.color(atPixel: CGPoint(x: 0, y: 0)), SnipPixelColor(red: 255, green: 0, blue: 0), "左上角为红")
    assertEqual(sampler.color(atPixel: CGPoint(x: 1, y: 0)), SnipPixelColor(red: 0, green: 255, blue: 0), "右上角为绿")
    assertEqual(sampler.color(atPixel: CGPoint(x: 0, y: 1)), SnipPixelColor(red: 0, green: 0, blue: 255), "左下角为蓝")
    assertEqual(sampler.color(atPixel: CGPoint(x: 1, y: 1)), SnipPixelColor(red: 255, green: 255, blue: 255), "右下角为白")
    assertEqual(sampler.color(atPixel: CGPoint(x: 2, y: 0)) == nil, true, "越界返回 nil")
    assertEqual(sampler.color(atPixel: CGPoint(x: -1, y: 0)) == nil, true, "负坐标返回 nil")
}
