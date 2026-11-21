import Foundation
import ImageIO
import NetworkMonitorCore
import UniformTypeIdentifiers

// MARK: - 截图写盘

/// 把 CGImage 按指定格式写盘 — 失败抛出而不是静默丢弃
///
/// 归属：截图服务层（NetworkMonitorFeatureSnip）。格式 / 质量口径全在 Core 的
/// `SnipImageFormat`，这里只做 ImageIO 落盘，不解读偏好。
public enum SnipFileWriter {

    /// 写盘失败原因（调用方据此决定提示文案，不与其它模块混用）
    public enum WriteError: Error {
        /// 目标路径建不出 ImageIO destination（目录不存在 / 无写权限 / 后缀对不上格式）
        case destinationUnavailable
        /// 编码或落盘收尾失败（磁盘满、卷被拔）
        case finalizeFailed
    }

    /// 按格式写盘：PNG 无损；JPEG 走质量参数（0…1，调用方先经 SnipImageFormat.clampedQuality）
    public static func write(_ image: CGImage,
                             to url: URL,
                             format: SnipImageFormat,
                             quality: Double = SnipImageFormat.defaultJPEGQuality) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL,
                                                                format.contentType.identifier as CFString,
                                                                1,
                                                                nil) else {
            throw WriteError.destinationUnavailable
        }
        var properties: [CFString: Any] = [:]
        if format == .jpeg {
            properties[kCGImageDestinationLossyCompressionQuality] = SnipImageFormat.clampedQuality(quality)
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw WriteError.finalizeFailed
        }
    }

    /// PNG 便捷入口（既有调用点保留，语义与 write(format: .png) 一致）
    public static func writePNG(_ image: CGImage, to url: URL) throws {
        try write(image, to: url, format: .png)
    }
}
