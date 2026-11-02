import CoreGraphics
import Foundation
import ImageIO
import NetworkMonitorCore
import UniformTypeIdentifiers

// MARK: - 图片像素守卫与预算（Core 纯函数）

/// 覆盖验收标准 A：像素守卫判据 + 解码字节预算 + 占位降级文案
func runClipboardImagePolicyTests() {
    print("🧪 Testing Clipboard image pixel policy...")

    // 1) 像素总数：边界值与溢出
    assertEqual(ClipboardImagePolicy.pixelCount(width: 12000, height: 12000), 144_000_000, "12000×12000 = 144MP")
    assertEqual(ClipboardImagePolicy.pixelCount(width: 0, height: 100), nil, "宽度 0 无像素数")
    assertEqual(ClipboardImagePolicy.pixelCount(width: 100, height: -1), nil, "负高度无像素数")
    assertEqual(ClipboardImagePolicy.pixelCount(width: Int.max, height: 2), nil, "乘法溢出返回 nil")

    // 2) 像素守卫：6K/8K 截图放行、12000×12000 拒绝
    assertEqual(ClipboardImagePolicy.rejection(width: 6000, height: 4000), nil, "6K 24MP 截图放行")
    assertEqual(ClipboardImagePolicy.rejection(width: 7680, height: 4320), nil, "8K 33MP 放行")
    assertEqual(ClipboardImagePolicy.rejection(width: 8000, height: 8000), nil, "64MP 整好在上限放行")
    assertEqual(ClipboardImagePolicy.rejection(width: 8001, height: 8000)?.kind, .pixelCountExceeded, "超过 64MP 被拒")
    assertEqual(ClipboardImagePolicy.rejection(width: 12000, height: 12000)?.kind,
                ClipboardImageRejection.Kind.pixelCountExceeded, "12000×12000 像素炸弹被拒")
    assertEqual(ClipboardImagePolicy.isAllowed(width: 12000, height: 12000), false, "像素炸弹不可用")
    assertEqual(ClipboardImagePolicy.rejection(width: 12000, height: 12000)?.pixelCount, 144_000_000, "拒绝原因带出像素总数")
    assertEqual(ClipboardImagePolicy.rejection(width: 12000, height: 12000)?.limit,
                ClipboardImagePolicy.maxPixelCount, "拒绝原因带出命中的上限")

    // 3) 极长条图：像素总数不多，但单边超限同样拒绝
    assertEqual(ClipboardImagePolicy.rejection(width: 1, height: 100_000)?.kind,
                ClipboardImageRejection.Kind.edgeExceeded, "1×100000 长条图按单边上限拒绝")
    assertEqual(ClipboardImagePolicy.rejection(width: 32_768, height: 1), nil, "单边整好在上限放行")

    // 4) 非法尺寸
    assertEqual(ClipboardImagePolicy.rejection(width: 0, height: 0)?.kind,
                ClipboardImageRejection.Kind.invalidDimensions, "0×0 判为尺寸非法")
    assertEqual(ClipboardImagePolicy.rejection(width: -5, height: 10)?.kind,
                ClipboardImageRejection.Kind.invalidDimensions, "负尺寸判为尺寸非法")

    // 5) 自定义阈值：≤ 0 归一化为默认值，正数生效
    assertEqual(ClipboardImagePolicy.rejection(width: 100, height: 100, maxPixelCount: 5_000)?.kind,
                ClipboardImageRejection.Kind.pixelCountExceeded, "自定义像素上限生效")
    assertEqual(ClipboardImagePolicy.rejection(width: 100, height: 100, maxPixelCount: 0), nil, "上限 ≤0 归一化为默认值")
    assertEqual(ClipboardImagePolicy.rejection(width: 100, height: 100, maxEdgePixels: 0), nil, "单边上限 ≤0 归一化为默认值")

    // 6) 缓存 cost 口径：解码后字节数
    assertEqual(ClipboardImagePolicy.decodedBytes(width: 320, height: 320), 409_600, "320×320 RGBA = 400KB")
    assertEqual(ClipboardImagePolicy.decodedBytes(width: 0, height: 320), 0, "非法尺寸 cost 为 0")
    assertEqual(ClipboardImagePolicy.decodedBytes(width: 12000, height: 12000), 576_000_000, "12000×12000 解码需 549MB")
    assertEqual(ClipboardImagePolicy.decodedBytes(width: 320, height: 320, bytesPerPixel: 0), 0, "每像素字节 ≤0 返回 0")
    assertEqual(ClipboardImagePolicy.decodedBytes(width: Int.max, height: 2), Int.max, "溢出按 Int.max 计（宁可被逐出）")

    // 7) 预算常量与文案
    assertEqual(ClipboardImagePolicy.thumbnailCacheCostLimit, 64 * 1024 * 1024, "缩略图缓存预算 64MB")
    assertEqual(ClipboardImagePolicy.thumbnailMaxEdge, 320, "缩略图最长边 320")
    assertEqual(ClipboardImagePolicy.maxPixelCount > 24_000_000, true, "像素上限高于 6K 截图，不误伤")
    assertEqual(ClipboardImagePolicy.rejection(width: 12000, height: 12000)?.placeholderPreview.contains("未保存原图"),
                true, "占位文案说明未保存原图")
    assertEqual(ClipboardImagePolicy.rejection(width: 0, height: 0)?.placeholderPreview, "图片无法识别（已跳过）", "尺寸非法占位文案")
    assertEqual(ClipboardImagePolicy.rejection(width: 12000, height: 12000)?.logDescription.isEmpty, false, "拒绝原因有排查描述")

    print("✅ Clipboard 图片像素守卫 works")
}

// MARK: - ImageIO 解码与落盘（端到端）

/// 覆盖验收标准 A/C：真实 PNG 走 ImageIO 读头部 + 缩略图，落盘扩展名取真实类型
func runClipboardImageStoreTests() {
    print("🧪 Testing Clipboard image store (ImageIO)...")
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("clipboard-image-tests", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    // 1) 32×16 的小图：落盘 + 缩略图 + 尺寸如实带回
    let small = makePNG(width: 32, height: 16)
    assertNotNil(small, "测试用 PNG 生成成功")
    guard let small else { exit(1) }
    assertEqual(ClipboardImageDecoder.pixelSize(of: small),
                ClipboardImageDecoder.PixelSize(width: 32, height: 16), "ImageIO 读头部得到 32×16")
    assertEqual(ClipboardImageDecoder.fileExtension(of: small), "png", "PNG 字节识别为 png 扩展名")

    let smallURL = directory.appendingPathComponent("small-source.png")
    try? small.write(to: smallURL)
    assertEqual(ClipboardImageDecoder.pixelSize(ofFileAt: smallURL.path),
                ClipboardImageDecoder.PixelSize(width: 32, height: 16), "文件路径也能读头部尺寸")

    // 2) 缩略图受最长边约束（小图不放大）
    let thumbnail = ClipboardImageDecoder.thumbnail(from: small)
    assertNotNil(thumbnail, "ImageIO 生成缩略图成功")
    if let thumbnail {
        assertEqual(max(thumbnail.width, thumbnail.height) <= 320, true, "缩略图最长边不超过 320")
    }
    assertNotNil(ClipboardImageDecoder.pngData(from: thumbnail ?? makeCGImage(width: 2, height: 2)!), "CGImage 可编成 PNG 字节")

    // 3) 空数据 / 非法字节不得崩溃，统一返回 nil
    assertEqual(ClipboardImageDecoder.pixelSize(of: Data()), nil, "空字节读不到尺寸")
    assertEqual(ClipboardImageDecoder.pixelSize(of: Data([1, 2, 3, 4])), nil, "非法字节读不到尺寸")
    assertEqual(ClipboardImageDecoder.cgImage(from: Data([1, 2, 3, 4])), nil, "非法字节解不出 CGImage")
    assertEqual(ClipboardImageDecoder.typeIdentifier(of: Data()), nil, "空字节无类型标识")

    print("✅ Clipboard 图片 ImageIO 解码 works")
}

// MARK: - 测试辅助

/// 生成纯色 PNG 字节（ImageIO 编码，不依赖磁盘）
func makePNG(width: Int, height: Int) -> Data? {
    guard let image = makeCGImage(width: width, height: height) else { return nil }
    let buffer = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(buffer, UTType.png.identifier as CFString, 1, nil) else {
        return nil
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return buffer as Data
}

/// 生成纯色 CGImage（测试夹具）
func makeCGImage(width: Int, height: Int) -> CGImage? {
    guard width > 0, height > 0,
          let context = CGContext(data: nil,
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