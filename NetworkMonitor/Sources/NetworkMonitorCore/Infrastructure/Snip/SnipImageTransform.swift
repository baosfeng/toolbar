import CoreGraphics

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
}
