import Foundation
import ImageIO
import NetworkMonitorCore
import UniformTypeIdentifiers

// MARK: - 截图写盘

/// 把 CGImage 按指定格式写盘 — 失败抛出而不是静默丢弃
enum SnipFileWriter {

    enum WriteError: Error {
        case destinationUnavailable
        case finalizeFailed
    }

    /// 按格式写盘：PNG 无损；JPEG 走质量参数（0…1，调用方先经 SnipImageFormat.clampedQuality）
    static func write(_ image: CGImage,
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
    static func writePNG(_ image: CGImage, to url: URL) throws {
        try write(image, to: url, format: .png)
    }
}
