import CoreGraphics
import Foundation

// MARK: - 像素颜色

/// 一个像素的 RGB 颜色 — 提供取色器需要的几种展示格式
public struct SnipPixelColor: Equatable, Sendable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// 形如 #FF8800
    public var hexString: String {
        String(format: "#%02X%02X%02X", red, green, blue)
    }

    /// 形如 RGB(255, 136, 0)
    public var rgbString: String {
        "RGB(\(red), \(green), \(blue))"
    }

    /// 取色器可切换的两种展示格式
    public enum DisplayFormat: Equatable, Sendable {
        case hex
        case rgb

        public func text(for color: SnipPixelColor) -> String {
            switch self {
            case .hex: return color.hexString
            case .rgb: return color.rgbString
            }
        }

        /// 下一个格式（Shift 切换用）：两种格式环形互切，按多少次都不会卡住
        public var next: DisplayFormat {
            switch self {
            case .hex: return .rgb
            case .rgb: return .hex
            }
        }

        /// 格式名 —— 挂在色值行尾，屏幕上能看见「现在是什么格式」
        ///
        /// 切换格式此前只改内部状态、屏上毫无反馈，用户不知道 Shift 生效了没有。
        public var hintText: String {
            switch self {
            case .hex: return "Hex"
            case .rgb: return "RGB"
            }
        }
    }
}

// MARK: - 放大镜信息条文案

/// 放大镜下方信息条的文案 —— 上行坐标、下行色值（先定位再取值）
public enum SnipMagnifierLabelText {

    /// 坐标行，形如「(1161, 282)」
    public static func coordinate(x: Int, y: Int) -> String {
        "(\(x), \(y))"
    }

    /// 色值行，形如「#F58C24 · Hex」——行尾格式名就是 Shift 切换的可见反馈
    public static func colorText(_ color: SnipPixelColor, format: SnipPixelColor.DisplayFormat) -> String {
        format.text(for: color) + " · " + format.hintText
    }
}

// MARK: - 像素采样

/// 截图像素采样 — 把任意格式的 CGImage 统一重绘为 RGBA8888 后再按像素坐标取色
///
/// 像素坐标一律按「图像左上为原点」传入；内部缓冲区行序与之一致。
public final class SnipPixelSampler: @unchecked Sendable {

    public let width: Int
    public let height: Int
    private let buffer: [UInt8]

    public init?(image: CGImage) {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        var storage = [UInt8](repeating: 0, count: width * height * 4)
        // 沿用源图色彩空间，避免重绘时做空间转换导致取色偏移
        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        // 显式大端 + alpha 在末字节 = RGBA，避免默认字节序在小端机器上变成 BGRA
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        let drawn: Bool = storage.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress,
                                          width: width,
                                          height: height,
                                          bitsPerComponent: 8,
                                          bytesPerRow: width * 4,
                                          space: colorSpace,
                                          bitmapInfo: bitmapInfo) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.width = width
        self.height = height
        self.buffer = storage
    }

    /// 按左上原点的像素坐标取色；越界返回 nil
    public func color(atPixel point: CGPoint) -> SnipPixelColor? {
        let x = Int(point.x.rounded(.down))
        let y = Int(point.y.rounded(.down))
        guard x >= 0, x < width, y >= 0, y < height else { return nil }
        // 缓冲区第 0 行对应图像顶行（实测 CGContext.draw 后行序自上而下），无需翻转
        let offset = (y * width + x) * 4
        guard offset + 2 < buffer.count else { return nil }
        return SnipPixelColor(red: buffer[offset], green: buffer[offset + 1], blue: buffer[offset + 2])
    }
}
