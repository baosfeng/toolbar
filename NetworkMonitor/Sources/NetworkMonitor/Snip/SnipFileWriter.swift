import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - 截图写盘

/// 把 CGImage 写成 PNG — 失败抛出而不是静默丢弃
enum SnipFileWriter {

    enum WriteError: Error {
        case destinationUnavailable
        case finalizeFailed
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL,
                                                               UTType.png.identifier as CFString,
                                                               1,
                                                               nil) else {
            throw WriteError.destinationUnavailable
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw WriteError.finalizeFailed
        }
    }
}
