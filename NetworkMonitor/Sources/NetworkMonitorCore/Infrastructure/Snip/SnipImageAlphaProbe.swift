import CoreGraphics
import Foundation

// MARK: - 贴图透明像素探测

/// 一张图里是否存在「没画满」的像素 —— 棋盘底的显示判据
///
/// 贴图窗是透明背景的浮窗：半透明 PNG 的透明区直接透出桌面，用户分不清
/// 「这块内容本来就是这样」还是「这块是透明的」。棋盘底只在这种情况下才值得画，
/// 全不透明的图（截图、照片）画了纯属噪音。
///
/// 判据只看 alpha 通道：任何像素 alpha < 255 即视为含透明区。
/// 重采样成 RGBA8888 是唯一可靠读 alpha 的方式（源图可能是任意像素格式）。
public enum SnipImageAlphaProbe {

    /// 该图是否含至少一个非全不透明像素
    ///
    /// 源图没有 alpha 通道时直接返回 false，省掉一次整图重绘。
    public static func hasTransparentPixels(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return false
        default:
            break
        }
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return false }
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        let drawn: Bool = buffer.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress,
                                          width: width,
                                          height: height,
                                          bitsPerComponent: 8,
                                          bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: bitmapInfo) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return false }
        for offset in stride(from: 3, to: buffer.count, by: 4) where buffer[offset] < 255 {
            return true
        }
        return false
    }
}
