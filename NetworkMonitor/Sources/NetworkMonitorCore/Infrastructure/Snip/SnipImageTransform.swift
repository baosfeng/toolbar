import CoreGraphics
import Foundation

// MARK: - 贴图图像变换

/// 贴图的旋转与镜像 — 直接重采样成新图，窗口尺寸随之调整
public enum SnipImageTransform {

    public static func rotated(_ image: CGImage, clockwise: Bool) -> CGImage? {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let newWidth = image.height
        let newHeight = image.width
        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(data: nil,
                                      width: newWidth,
                                      height: newHeight,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: colorSpace,
                                      bitmapInfo: bitmapInfo) else {
            return nil
        }
        context.interpolationQuality = .high
        context.translateBy(x: CGFloat(newWidth) / 2, y: CGFloat(newHeight) / 2)
        context.rotate(by: clockwise ? -CGFloat.pi / 2 : CGFloat.pi / 2)
        context.translateBy(x: -width / 2, y: -height / 2)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    public static func mirrored(_ image: CGImage, horizontal: Bool) -> CGImage? {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(data: nil,
                                      width: image.width,
                                      height: image.height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: colorSpace,
                                      bitmapInfo: bitmapInfo) else {
            return nil
        }
        context.interpolationQuality = .high
        if horizontal {
            context.translateBy(x: width, y: 0)
            context.scaleBy(x: -1, y: 1)
        } else {
            context.translateBy(x: 0, y: height)
            context.scaleBy(x: 1, y: -1)
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    // MARK: - 灰度与反色

    /// 灰度（Rec.601 亮度加权）
    ///
    /// 加权口径自己定并写死：Y = 0.299R + 0.587G + 0.114B（ITU-R BT.601），
    /// 四舍五入到整数。之所以不直接把图像画进 DeviceGray 色彩空间：那条路走的是
    /// CoreGraphics 的线性光亮度，取值与 Rec.601 不同、各系统版本也不保证一致，
    /// 测试就没法逐像素断言。这里先经 CGContext 重绘成 RGBA8888（色彩空间兜底、
    /// 高质量插值），再按上式逐像素算，最后用 CGDataProvider 产回 CGImage。
    ///
    /// alpha 原样保留；缓冲区是预乘 alpha，算之前先还原成直通值、算完再乘回去，
    /// 半透明像素的灰度才不会比不透明的同色像素暗一截。
    public static func grayscale(_ image: CGImage) -> CGImage? {
        guard var buffer = rgbaBuffer(of: image) else { return nil }
        let width = image.width
        let height = image.height
        for offset in stride(from: 0, to: buffer.count, by: 4) {
            let alpha = Int(buffer[offset + 3])
            let red = unpremultiplied(Int(buffer[offset]), alpha: alpha)
            let green = unpremultiplied(Int(buffer[offset + 1]), alpha: alpha)
            let blue = unpremultiplied(Int(buffer[offset + 2]), alpha: alpha)
            let luma = (299 * red + 587 * green + 114 * blue + 500) / 1000
            let premultiplied = (luma * alpha + 127) / 255
            buffer[offset] = UInt8(clamping: premultiplied)
            buffer[offset + 1] = UInt8(clamping: premultiplied)
            buffer[offset + 2] = UInt8(clamping: premultiplied)
        }
        return makeImage(from: buffer, width: width, height: height)
    }

    /// 反色（每个通道取补，alpha 不动）
    ///
    /// 与灰度同一条路径：重绘成 RGBA8888 后逐像素取补再产回 CGImage。
    /// 缓冲区是预乘 alpha，直通值取补等价于预乘值直接取补（C' · a = a − C · a），
    /// 因此这里直接用 `alpha − 通道值`，不必先还原再乘回。
    public static func inverted(_ image: CGImage) -> CGImage? {
        guard var buffer = rgbaBuffer(of: image) else { return nil }
        let width = image.width
        let height = image.height
        for offset in stride(from: 0, to: buffer.count, by: 4) {
            let alpha = Int(buffer[offset + 3])
            buffer[offset] = UInt8(clamping: alpha - Int(buffer[offset]))
            buffer[offset + 1] = UInt8(clamping: alpha - Int(buffer[offset + 1]))
            buffer[offset + 2] = UInt8(clamping: alpha - Int(buffer[offset + 2]))
        }
        return makeImage(from: buffer, width: width, height: height)
    }

    // MARK: - 像素缓冲（灰度 / 反色共用的三段：读、改、写回）

    /// 把任意 CGImage 重绘成 RGBA8888（大端、alpha 在末字节）的字节缓冲

    /// 色彩空间沿用源图、找不到了才回落 DeviceRGB，避免多一次空间转换带来色偏。
    private static func rgbaBuffer(of image: CGImage) -> [UInt8]? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        let drawn: Bool = buffer.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress,
                                          width: width,
                                          height: height,
                                          bitsPerComponent: 8,
                                          bytesPerRow: width * 4,
                                          space: colorSpace,
                                          bitmapInfo: bitmapInfo) else {
                return false
            }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? buffer : nil
    }

    /// 字节缓冲 → CGImage（输出统一 DeviceRGB，取值不再被源图色彩空间解释一次）
    private static func makeImage(from buffer: [UInt8], width: Int, height: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(buffer) as CFData) else { return nil }
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        return CGImage(width: width,
                       height: height,
                       bitsPerComponent: 8,
                       bitsPerPixel: 32,
                       bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
                       provider: provider,
                       decode: nil,
                       shouldInterpolate: false,
                       intent: .defaultIntent)
    }

    /// 预乘通道值 → 直通值（alpha 为 0 时直通值没有意义，按全黑处理）
    private static func unpremultiplied(_ channel: Int, alpha: Int) -> Int {
        guard alpha > 0 else { return 0 }
        guard alpha < 255 else { return channel }
        return min(255, (channel * 255 + alpha / 2) / alpha)
    }
}
