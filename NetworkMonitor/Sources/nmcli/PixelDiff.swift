import CoreGraphics
import Foundation
import ImageIO

// MARK: - 像素对比

/// 两张 PNG 的差异比例 — `assert pixels` 与场景里「悬停真的变了」都靠它
enum PixelDiff {

    /// 差异比例（0…1）：尺寸不同直接判 1（视为完全不同）
    ///
    /// 口径：逐像素取 RGB 三通道最大差值，超过 8/255 记为该像素不同。
    /// 阈值 8 是为了放过 PNG 编码与亚像素抗锯齿的噪声，同时仍能抓住「明显变了」。
    static func ratio(_ pathA: String, _ pathB: String) throws -> Double {
        guard let imageA = load(pathA), let imageB = load(pathB) else {
            throw CLIError("像素对比读图失败：\(pathA) / \(pathB)")
        }
        guard imageA.width == imageB.width, imageA.height == imageB.height else { return 1 }
        let count = imageA.width * imageA.height
        var differing = 0
        for index in 0..<count {
            let base = index * 4
            let dr = abs(Int(imageA.pixels[base]) - Int(imageB.pixels[base]))
            let dg = abs(Int(imageA.pixels[base + 1]) - Int(imageB.pixels[base + 1]))
            let db = abs(Int(imageA.pixels[base + 2]) - Int(imageB.pixels[base + 2]))
            if max(dr, max(dg, db)) > 8 { differing += 1 }
        }
        return Double(differing) / Double(count)
    }

    private struct Raster {
        let width: Int
        let height: Int
        let pixels: [UInt8]
    }

    private static func load(_ path: String) -> Raster? {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress,
                                          width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        return Raster(width: width, height: height, pixels: pixels)
    }
}
