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

    // Shift 切换是环形：两种格式互切，按多少次都不会卡住
    assertEqual(SnipPixelColor.DisplayFormat.hex.next, .rgb, "hex 切到 rgb")
    assertEqual(SnipPixelColor.DisplayFormat.rgb.next, .hex, "rgb 切回 hex")
    assertEqual(SnipPixelColor.DisplayFormat.hex.next.next, .hex, "连按两次回到原格式")

    // 格式名非空且与取值不同：它是行尾的「现在是什么格式」提示，不能与色值文字撞脸
    for format in [SnipPixelColor.DisplayFormat.hex, .rgb] {
        assertEqual(format.hintText.isEmpty, false, "格式名非空")
        assertEqual(format.hintText == format.text(for: red), false, "格式名与色值文字不同")
    }
    assertEqual(SnipPixelColor.DisplayFormat.hex.hintText, "Hex", "hex 的格式名")
    assertEqual(SnipPixelColor.DisplayFormat.rgb.hintText, "RGB", "rgb 的格式名")

    // 放大镜两行信息条：上行坐标、下行色值 + 格式名（先定位再取值）
    assertEqual(SnipMagnifierLabelText.coordinate(x: 1161, y: 282), "(1161, 282)", "坐标行文案")
    assertEqual(SnipMagnifierLabelText.colorText(red, format: .hex), "#FF0000 · Hex", "色值行带 hex 格式名")
    assertEqual(SnipMagnifierLabelText.colorText(red, format: .rgb), "RGB(255, 0, 0) · RGB", "色值行带 rgb 格式名")

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
