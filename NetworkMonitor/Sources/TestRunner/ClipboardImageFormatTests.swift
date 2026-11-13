import CoreGraphics
import Foundation
import NetworkMonitorCore

// MARK: - 剪贴板图片格式兼容（Core 纯函数）

/// 覆盖规格 2.1「增量 A」：白名单 + 统一类型系统兜底的候选排序、归一化与多表示编码
func runClipboardImageFormatTests() {
    print("🧪 Testing Clipboard image format compatibility...")
    runImageFormatWhitelistTests()
    runImageFormatNormalizationTests()
    runImageFormatFallbackTests()
    runImageFormatSelectionTests()
    runImageWritePolicyTests()
    runImageEncodingRoundTripTests()
    print("✅ Clipboard 图片格式兼容（白名单 / 归一化 / 兜底 / 三表示编码）works")
}

// MARK: - 白名单命中与顺序

/// 白名单八类每类都能命中，且输出顺序与白名单优先级一致（PNG 最优先，BMP 最后）
private func runImageFormatWhitelistTests() {
    let whitelist = ClipboardImageFormat.whitelistedTypeNames
    assertEqual(whitelist.count, 8, "白名单八类（png/tiff/jpeg/heic/heif/webp/gif/bmp）")
    assertEqual(whitelist.first, "public.png", "白名单首项仍是 PNG（既有「PNG 优先」语义不变）")
    assertEqual(whitelist[1], "public.tiff", "白名单次项仍是 TIFF（既有兜底语义不变）")

    // 每类单独命中：入参只有一个类型名时必然命中它自己
    for typeName in whitelist {
        assertEqual(ClipboardImageFormat.orderedCandidates(from: [typeName]), [typeName],
                    "白名单类型 \(typeName) 单独命中")
    }

    // 乱序入参 → 输出按白名单优先级重排
    let shuffled = ["com.microsoft.bmp", "com.compuserve.gif", "public.tiff", "public.png"]
    assertEqual(ClipboardImageFormat.orderedCandidates(from: shuffled),
                ["public.png", "public.tiff", "com.compuserve.gif", "com.microsoft.bmp"],
                "入参乱序按白名单优先级重排")
    assertEqual(ClipboardImageFormat.orderedCandidates(from: ["public.heif", "public.heic"]),
                ["public.heic", "public.heif"], "HEIC 优先于 HEIF")
    assertEqual(ClipboardImageFormat.orderedCandidates(from: ["org.webmproject.webp", "public.jpeg"]),
                ["public.jpeg", "org.webmproject.webp"], "JPEG 优先于 WebP")

    // 同类大小写/空白变体只算一个，输出规范名
    assertEqual(ClipboardImageFormat.orderedCandidates(from: ["PUBLIC.PNG"]), ["public.png"],
                "大写变体归一化后输出白名单规范名")
    assertEqual(ClipboardImageFormat.orderedCandidates(from: [" public.TIFF  "]), ["public.tiff"],
                "前后空白被剥掉后命中 TIFF")
    assertEqual(ClipboardImageFormat.orderedCandidates(from: ["public.png", "PUBLIC.PNG", " public.Png "]),
                ["public.png"], "同一类型的三种写法去重后只剩一项")

    // 真实复制场景：PNG + TIFF 同时登记时仍只认 PNG（同一次复制只取一种表示）
    assertEqual(ClipboardImageFormat.orderedCandidates(from: ["public.tiff", "public.png"]).first, "public.png",
                "PNG 与 TIFF 并存时首选 PNG")

    print("✅ Clipboard 图片格式白名单（八类命中 / 优先级重排）works")
}

// MARK: - 归一化

private func runImageFormatNormalizationTests() {
    assertEqual(ClipboardImageFormat.normalized("  Public.PNG\n"), "public.png", "去首尾空白并转小写")
    assertEqual(ClipboardImageFormat.normalized("public.png"), "public.png", "规范名原样返回")
    assertEqual(ClipboardImageFormat.normalized(""), nil, "空串判为无类型")
    assertEqual(ClipboardImageFormat.normalized("   \t "), nil, "全空白判为无类型")
    assertEqual(ClipboardImageFormat.normalized("Public.Jpeg"), "public.jpeg", "JPEG 大写归一化")

    print("✅ Clipboard 图片格式归一化（大小写 / 空白 / 空串）works")
}

// MARK: - 白名单外但归入 image 的类型兜底

private func runImageFormatFallbackTests() {
    // 白名单外的图片类型：统一类型系统判为 image 即应进入候选（正向兜底，不是黑名单排除）
    for typeName in ["public.avif", "com.apple.icns", "public.jpeg-2000"] {
        assertEqual(ClipboardImageFormat.isImageType(typeName), true, "\(typeName) 归入图片")
    }
    assertEqual(ClipboardImageFormat.orderedCandidates(from: ["public.avif"]), ["public.avif"],
                "白名单外但 image 类型进入候选")
    assertEqual(ClipboardImageFormat.orderedCandidates(from: ["public.png", "public.avif"]),
                ["public.png", "public.avif"], "白名单命中排在前，兜底排在后面")
    assertEqual(ClipboardImageFormat.orderedCandidates(from: ["public.avif", "com.apple.icns", "public.png"]),
                ["public.png", "public.avif", "com.apple.icns"], "多个兜底类型按入参顺序追加")

    // 非图片类型不进候选
    for typeName in ["public.utf8-plain-text", "public.rtf", "public.file-url", "org.xiph.ogg"] {
        assertEqual(ClipboardImageFormat.isImageType(typeName), false, "\(typeName) 不是图片")
    }
    assertEqual(ClipboardImageFormat.isImageType("not.a.uttype.at.all"), false, "未登记类型名判为不是图片")
    assertEqual(ClipboardImageFormat.isImageType(""), false, "空类型名判为不是图片")
    assertEqual(ClipboardImageFormat.isImageType("public.data"), false, "public.data 不是图片（不能用宽泛类型冒充）")

    print("✅ Clipboard 图片格式兜底（白名单外 image 类型 / 非图片排除）works")
}

// MARK: - 首个可读表示

private func runImageFormatSelectionTests() {
    // 纯文本剪贴板：无候选（调用方据此走既有文本降级）
    let textOnly = ["public.utf8-plain-text", "NSStringPboardType"]
    assertEqual(ClipboardImageFormat.orderedCandidates(from: textOnly).isEmpty, true, "纯文本类型返回空候选")
    assertEqual(ClipboardImageFormat.firstReadableCandidate(in: textOnly, read: { _ in Data([1]) }), nil,
                "纯文本类型取不到图片表示")

    // 空数组 / 全空白数组
    assertEqual(ClipboardImageFormat.orderedCandidates(from: []).isEmpty, true, "空数组返回空候选")
    assertEqual(ClipboardImageFormat.orderedCandidates(from: ["", "   ", "\t"]).isEmpty, true,
                "全空白类型名返回空候选")
    assertEqual(ClipboardImageFormat.firstReadableCandidate(in: [], read: { _ in Data([1]) }), nil,
                "空数组取不到表示")

    // 取字节：PNG 有数据、TIFF 为空 → 选中 PNG；两者都为空 → nil（继续走降级）
    let both = ["public.tiff", "public.png"]
    let pngWins = ClipboardImageFormat.firstReadableCandidate(in: both, read: { name in
        name == "public.png" ? Data([1, 2, 3]) : Data()
    })
    assertEqual(pngWins?.typeName, "public.png", "PNG 有字节时优先选 PNG（空数据视为不可用）")
    assertEqual(pngWins?.data, Data([1, 2, 3]), "带回的就是该表示原始字节")

    let tiffWins = ClipboardImageFormat.firstReadableCandidate(in: both, read: { name in
        name == "public.tiff" ? Data([9]) : nil
    })
    assertEqual(tiffWins?.typeName, "public.tiff", "PNG 缺失时兜底 TIFF（大小写归一后仍能取到）")

    // 大小写/空白变体：候选输出规范名，取值时按等价原始写法兜底
    let lookups = ClipboardImageFormat.dataLookupNames(for: "public.png", in: ["  Public.PNG ", "public.heic"])
    assertEqual(lookups, ["public.png", "Public.PNG"], "取值类型名含规范名与等价原始写法，且不跨类型")
    let mixedCase = ClipboardImageFormat.firstReadableCandidate(in: ["  Public.PNG "], read: { name in
        name == "Public.PNG" ? Data([7]) : nil
    })
    assertEqual(mixedCase?.typeName, "public.png", "仅登记大写变体时仍命中并带回规范名")
    assertEqual(ClipboardImageFormat.dataLookupNames(for: "", in: ["public.png"]), [], "空候选返回空取值名")

    // 三种全失败（read 全返回 nil）
    assertEqual(ClipboardImageFormat.firstReadableCandidate(in: both, read: { _ in nil }), nil,
                "所有候选都取不到字节时返回 nil，走既有降级")

    print("✅ Clipboard 图片格式取值（首个可读 / 空数据跳过 / 全失败降级）works")
}

// MARK: - 回写表示策略

/// 回写是否补一份 JPEG：原图为 JPEG 时补，PNG / TIFF 都失败时由 JPEG 兜底
private func runImageWritePolicyTests() {
    assertEqual(ClipboardImageFormat.jpegTypeName, "public.jpeg", "JPEG 类型名统一取自常量")
    assertEqual(ClipboardImageFormat.isJPEGType(nil), false, "空类型标识不是 JPEG")
    assertEqual(ClipboardImageFormat.isJPEGType(""), false, "空串不是 JPEG")
    assertEqual(ClipboardImageFormat.isJPEGType("public.jpeg"), true, "public.jpeg 判为 JPEG")
    assertEqual(ClipboardImageFormat.isJPEGType("  PUBLIC.JPEG "), true, "大小写与空白归一后仍判为 JPEG")
    assertEqual(ClipboardImageFormat.isJPEGType("public.png"), false, "PNG 不判为 JPEG")
    assertEqual(ClipboardImageFormat.isJPEGType("public.heic"), false, "HEIC 不判为 JPEG")

    assertEqual(ClipboardImageFormat.shouldWriteJPEG(sourceIsJPEG: false, pngAvailable: true, tiffAvailable: true),
                false, "PNG + TIFF 正常且原图非 JPEG 时不写 JPEG")
    assertEqual(ClipboardImageFormat.shouldWriteJPEG(sourceIsJPEG: true, pngAvailable: true, tiffAvailable: true),
                true, "原图本身是 JPEG 时额外写一份 JPEG")
    assertEqual(ClipboardImageFormat.shouldWriteJPEG(sourceIsJPEG: false, pngAvailable: false, tiffAvailable: false),
                true, "PNG / TIFF 都编码失败时由 JPEG 兜底")
    assertEqual(ClipboardImageFormat.shouldWriteJPEG(sourceIsJPEG: false, pngAvailable: true, tiffAvailable: false),
                false, "仅 TIFF 失败时不必再写 JPEG（PNG 已可用）")

    print("✅ Clipboard 图片回写表示策略（JPEG 条件写入 / 兜底）works")
}

// MARK: - 三种编码往返

/// tiffData / jpegData 编出的字节必须能被 ImageIO 读回原尺寸（回写多表示的前提）
private func runImageEncodingRoundTripTests() {
    let expected = ClipboardImageDecoder.PixelSize(width: 64, height: 32)
    assertEqual(ClipboardImageDecoder.pixelSize(of: Data()), nil, "空字节读不到尺寸（编码失败基线）")

    guard let image = makeCGImage(width: 64, height: 32) else {
        print("❌ 测试夹具 CGImage 生成失败")
        exit(1)
    }

    // PNG：既有实现，回归确认
    guard let png = ClipboardImageDecoder.pngData(from: image) else {
        print("❌ PNG 编码失败")
        exit(1)
    }
    assertEqual(ClipboardImageDecoder.pixelSize(of: png), expected, "PNG 编码后读回 64×32")

    // TIFF：新增编码，尺寸必须与解码结果一致
    guard let tiff = ClipboardImageDecoder.tiffData(from: image) else {
        print("❌ TIFF 编码失败")
        exit(1)
    }
    assertEqual(ClipboardImageDecoder.pixelSize(of: tiff), expected, "tiffData 编码后 pixelSize 可读回原尺寸")
    assertEqual(ClipboardImageDecoder.fileExtension(of: tiff), "tiff", "TIFF 字节识别为 tiff 扩展名")
    assertEqual(ClipboardImageDecoder.cgImage(from: Data([1, 2, 3, 4])) == nil, true, "非法字节解不出 CGImage")

    // JPEG：新增有损编码，尺寸不变；质量参数越界自动收进 0...1
    guard let jpeg = ClipboardImageDecoder.jpegData(from: image) else {
        print("❌ JPEG 编码失败")
        exit(1)
    }
    assertEqual(ClipboardImageDecoder.pixelSize(of: jpeg), expected, "jpegData 编码后 pixelSize 可读回原尺寸")
    // public.jpeg 的首选扩展名由系统给（jpg 或 jpeg），只断言落在 JPEG 家族内
    assertEqual(["jpg", "jpeg"].contains(ClipboardImageDecoder.fileExtension(of: jpeg) ?? ""), true,
                "JPEG 字节识别为 jpeg 家族扩展名")
    let jpegLow = ClipboardImageDecoder.jpegData(from: image, compressionQuality: -1)
    let jpegHigh = ClipboardImageDecoder.jpegData(from: image, compressionQuality: 2)
    assertNotNil(jpegLow, "质量参数 -1 收进 0 仍可编码")
    assertNotNil(jpegHigh, "质量参数 2 收进 1 仍可编码")

    // 三表示字节互不相同（不是同一份数据伪装成三种类型）
    let signatures = Set([png, tiff, jpeg].map { "\($0.count)-\($0.hashValue)" })
    assertEqual(signatures.count, 3, "PNG / TIFF / JPEG 三种表示字节彼此不同")

    print("✅ Clipboard 图片多表示编码（PNG / TIFF / JPEG 往返尺寸）works")
}
