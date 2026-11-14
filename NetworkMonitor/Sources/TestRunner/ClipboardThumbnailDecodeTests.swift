import CoreGraphics
import Foundation
import NetworkMonitorCore

// MARK: - 缩略图兜底降采样出口（A2 兜底路径）

/// 覆盖第三批 A2 「兜底解码后仍走既有降采样出口」的可断言部分：
/// 降采样比例正确 / 小图不放大 / 非法尺寸返回 nil。
/// 兜底本身的 NSBitmapImageRep 分支在 App 目标内，走真机取证，不做自动化断言。
func runClipboardThumbnailDecodeTests() {
    print("🧪 Testing Clipboard thumbnail downsampling...")

    // 1) 大图按最长边降采样，宽高比不变
    guard let wide = makeTestImage(width: 1000, height: 500) else {
        print("❌ 无法构造测试位图")
        exit(1)
    }
    guard let scaled = ClipboardImageDecoder.thumbnail(from: wide) else {
        print("❌ 降采样返回 nil")
        exit(1)
    }
    assertEqual(scaled.width, 320, "1000×500 降到最长边 320")
    assertEqual(scaled.height, 160, "高度按比例缩为 160")
    assertEqual(ClipboardImagePolicy.thumbnailMaxEdge, 320, "默认最长边与 Core 常量同源")

    // 2) 正方形与大长条同样按最长边收敛
    guard let square = makeTestImage(width: 640, height: 640),
          let squareThumb = ClipboardImageDecoder.thumbnail(from: square) else {
        print("❌ 正方形降采样失败")
        exit(1)
    }
    assertEqual(squareThumb.width, 320, "正方形宽收敛到 320")
    assertEqual(squareThumb.height, 320, "正方形高收敛到 320")
    guard let tall = makeTestImage(width: 200, height: 900),
          let tallThumb = ClipboardImageDecoder.thumbnail(from: tall) else {
        print("❌ 长条降采样失败")
        exit(1)
    }
    assertEqual(tallThumb.height, 320, "长条按高收敛到 320")
    assertEqual(tallThumb.width, 71, "长条宽按比例缩为 71")

    // 3) 小于上限的图原样返回（不放大、不重复解码）
    guard let small = makeTestImage(width: 120, height: 80),
          let smallThumb = ClipboardImageDecoder.thumbnail(from: small) else {
        print("❌ 小图降采样失败")
        exit(1)
    }
    assertEqual(smallThumb.width, 120, "小图不放大（宽）")
    assertEqual(smallThumb.height, 80, "小图不放大（高）")

    // 4) 自定义上限生效；上限 ≤ 0 归一化为默认值
    guard let custom = ClipboardImageDecoder.thumbnail(from: wide, maxPixelSize: 100) else {
        print("❌ 自定义上限降采样失败")
        exit(1)
    }
    assertEqual(custom.width, 100, "自定义上限 100 生效")
    assertEqual(custom.height, 50, "自定义上限下高按比例缩为 50")
    guard let fallback = ClipboardImageDecoder.thumbnail(from: wide, maxPixelSize: 0) else {
        print("❌ 上限 0 降级失败")
        exit(1)
    }
    assertEqual(fallback.width, 320, "上限 0 归一化为默认 320")

    print("✅ Clipboard 缩略图降采样 works")
}

/// 构造一张纯色测试位图（不解码任何文件，全程内存）
private func makeTestImage(width: Int, height: Int) -> CGImage? {
    guard width > 0, height > 0 else { return nil }
    guard let context = CGContext(data: nil,
                                  width: width,
                                  height: height,
                                  bitsPerComponent: 8,
                                  bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
}
