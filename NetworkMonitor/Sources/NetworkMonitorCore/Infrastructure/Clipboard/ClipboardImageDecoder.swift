import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - ImageIO 解码工具

/// 图片解码工具 — 全程走 ImageIO，禁止 NSImage + tiffRepresentation 全量解压
///
/// 为什么不用 NSImage：NSImage(contentsOf:) 只读头部，但一旦取 tiffRepresentation /
/// cgImage(forProposedRect:) 就会把整张位图展开（12000×12000 RGBA ≈ 549MB，实测峰值 2764MB）。
/// ImageIO 的缩略图 API 在解码管线内直接降采样，同一张图峰值只有 16MB 量级。
/// 本类型只做解码，不负责落盘与缓存（见 ClipboardImageStore / ClipboardCardView）。
public enum ClipboardImageDecoder {

    /// 像素尺寸（不含任何 CoreGraphics 对象，可跨线程传递）
    public struct PixelSize: Equatable, Sendable {
        /// 像素宽
        public let width: Int
        /// 像素高
        public let height: Int

        public init(width: Int, height: Int) {
            self.width = width
            self.height = height
        }
    }

    // MARK: 头部元数据

    /// 读字节流头部取像素尺寸（不解码像素；调用方负责先做像素守卫）
    public static func pixelSize(of data: Data) -> PixelSize? {
        guard !data.isEmpty else { return nil }
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else { return nil }
        return pixelSize(of: source)
    }

    /// 读文件头部取像素尺寸（不解码像素；文件不存在或格式不识别返回 nil）
    public static func pixelSize(ofFileAt path: String) -> PixelSize? {
        guard let source = imageSource(ofFileAt: path) else { return nil }
        return pixelSize(of: source)
    }

    /// 从已打开的图像源读头部属性
    private static func pixelSize(of source: CGImageSource) -> PixelSize? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0 else { return nil }
        return PixelSize(width: width, height: height)
    }

    // MARK: 文件类型

    /// 文件内容的真实类型标识（如 public.png / public.tiff），用于修正「后缀写死 .png」的缺陷
    public static func typeIdentifier(ofFileAt path: String) -> String? {
        guard let source = imageSource(ofFileAt: path) else { return nil }
        return CGImageSourceGetType(source) as String?
    }

    /// 字节流的真实类型标识（落盘前判定真实扩展名，避免 PNG 文件里装 TIFF 字节）
    public static func typeIdentifier(of data: Data) -> String? {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceGetType(source) as String?
    }

    /// 真实扩展名（无法识别返回 nil，由调用方决定兜底）
    public static func fileExtension(of data: Data) -> String? {
        guard let identifier = typeIdentifier(of: data), let type = UTType(identifier) else { return nil }
        return type.preferredFilenameExtension
    }

    // MARK: 解码

    /// 按最长边生成缩略图（ImageIO 内部降采样，不展开原图位图）
    /// - Parameters:
    ///   - path: 原图路径
    ///   - maxPixelSize: 最长边像素上限（≤ 0 时取默认 320）
    public static func thumbnail(fromFileAt path: String,
                          maxPixelSize: Int = ClipboardImagePolicy.thumbnailMaxEdge) -> CGImage? {
        guard let source = imageSource(ofFileAt: path) else { return nil }
        let edge = maxPixelSize > 0 ? maxPixelSize : ClipboardImagePolicy.thumbnailMaxEdge
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: edge,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// 按最长边从字节流生成缩略图（落盘后用原始字节直接缩，省一次读文件）
    public static func thumbnail(from data: Data,
                          maxPixelSize: Int = ClipboardImagePolicy.thumbnailMaxEdge) -> CGImage? {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let edge = maxPixelSize > 0 ? maxPixelSize : ClipboardImagePolicy.thumbnailMaxEdge
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: edge,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// 直读原图 CGImage（贴图 / 回写用；调用方必须先过像素守卫，否则等于自己造像素炸弹）
    public static func cgImage(fromFileAt path: String) -> CGImage? {
        guard let source = imageSource(ofFileAt: path) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    /// 直读字节流 CGImage（调用方必须先过像素守卫）
    public static func cgImage(from data: Data) -> CGImage? {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    // MARK: 守卫式解码

    /// 过像素守卫后直读原图文件（贴图 / 回写等必须解全图的场景）
    /// - Returns: 尺寸非法、超像素上限或解码失败都返回 nil
    public static func guardedCGImage(fromFileAt path: String) -> CGImage? {
        guard let size = pixelSize(ofFileAt: path),
              ClipboardImagePolicy.isAllowed(width: size.width, height: size.height) else { return nil }
        return cgImage(fromFileAt: path)
    }

    /// 过像素守卫后直读字节流原图（同上）
    public static func guardedCGImage(from data: Data) -> CGImage? {
        guard let size = pixelSize(of: data),
              ClipboardImagePolicy.isAllowed(width: size.width, height: size.height) else { return nil }
        return cgImage(from: data)
    }

    // MARK: 编码

    /// CGImage 编成 PNG 字节（回写剪贴板用）
    public static func pngData(from image: CGImage) -> Data? {
        encode(image, as: .png)
    }

    /// CGImage 编成 TIFF 字节（回写剪贴板用，供只认 TIFF 的老 App 粘贴）
    public static func tiffData(from image: CGImage) -> Data? {
        encode(image, as: .tiff)
    }

    /// CGImage 编成 JPEG 字节（回写剪贴板用，质量 0.9）
    public static func jpegData(from image: CGImage, compressionQuality: Double = 0.9) -> Data? {
        let quality = min(max(compressionQuality, 0), 1)
        let options = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        return encode(image, as: .jpeg, options: options)
    }

    // MARK: 内部实现（编码）

    /// 统一 ImageIO 编码入口：三种表示复用同一条目的地管线，只有目标类型与选项不同
    private static func encode(_ image: CGImage, as type: UTType, options: CFDictionary? = nil) -> Data? {
        let buffer = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            buffer, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, options)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return buffer as Data
    }

    // MARK: 内部实现

    /// 打开图像源（只建索引，不读像素）
    private static func imageSource(ofFileAt path: String) -> CGImageSource? {
        guard !path.isEmpty else { return nil }
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        return CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, options)
    }
}