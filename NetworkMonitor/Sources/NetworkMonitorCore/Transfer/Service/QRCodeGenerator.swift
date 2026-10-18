import CoreGraphics
import CoreImage
import Foundation
import ImageIO

// MARK: - 二维码生成

/// 二维码生成 — 纯逻辑（CoreImage `CIQRCodeGenerator`），不依赖 AppKit
///
/// 输出 PNG 字节，UI 侧用 `NSImage(data:)` 直接展示，测试侧校验 PNG 头与尺寸。
public enum QRCodeGenerator {

    /// 纠错级别（M 兼顾容量与容错）
    public static let correctionLevel = "M"

    /// 生成二维码 PNG；空文本或渲染失败返回 nil
    ///
    /// - Parameters:
    ///   - text: 二维码内容（扫码链接）
    ///   - scale: 放大倍数（二维码原始尺寸很小，需放大后才能清晰显示）
    public static func pngData(for text: String, scale: CGFloat = 10) -> Data? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, scale > 0 else { return nil }
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(trimmed.utf8), forKey: "inputMessage")
        filter.setValue(correctionLevel, forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }

        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let extent = scaled.extent.integral
        guard extent.width >= 1, extent.height >= 1 else { return nil }

        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(scaled, from: extent) else { return nil }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
