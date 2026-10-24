import CoreGraphics
import CoreImage
import Foundation

// MARK: - 马赛克与模糊

/// 马赛克 / 高斯模糊的像素处理 — 输入像素矩形，输出可直接绘制的小图
public enum SnipMosaicProcessor {

    /// 马赛克块边长（像素）
    public static let defaultBlockSize: CGFloat = 14
    /// 高斯模糊半径（像素）
    public static let defaultBlurRadius: CGFloat = 14

    private static let ciContext = CIContext(options: nil)

    /// 像素化：先缩到小尺寸再按块放大，调用方需用 .none 插值绘制
    public static func pixelated(_ image: CGImage, in pixelRect: CGRect, blockSize: CGFloat = defaultBlockSize) -> CGImage? {
        guard let cropped = image.cropping(to: pixelRect) else { return nil }
        let block = max(blockSize, 2)
        let columns = max(Int((pixelRect.width / block).rounded()), 1)
        let rows = max(Int((pixelRect.height / block).rounded()), 1)
        let colorSpace = cropped.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(data: nil,
                                      width: columns,
                                      height: rows,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: colorSpace,
                                      bitmapInfo: bitmapInfo) else {
            return nil
        }
        // 缩小时用平滑采样得到块内平均色；放大时由调用方设为 .none 保持方块感
        context.interpolationQuality = .high
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: CGFloat(columns), height: CGFloat(rows)))
        return context.makeImage()
    }

    /// 高斯模糊：走 CoreImage，结果裁回原尺寸
    public static func blurred(_ image: CGImage, in pixelRect: CGRect, radius: CGFloat = defaultBlurRadius) -> CGImage? {
        guard let cropped = image.cropping(to: pixelRect) else { return nil }
        let input = CIImage(cgImage: cropped)
        let clamped = input.clampedToExtent()
        let filtered = clamped.applyingFilter("CIGaussianBlur",
                                              parameters: [kCIInputRadiusKey: max(radius, 1)])
        guard let output = ciContext.createCGImage(filtered, from: input.extent) else { return nil }
        return output
    }
}
