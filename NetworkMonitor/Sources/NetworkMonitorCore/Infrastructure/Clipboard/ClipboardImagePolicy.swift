import Foundation

// MARK: - 图片像素守卫

/// 图片像素守卫的拒绝原因 — App 层据此拼日志与占位文案
///
/// 该类型是纯值类型：不含 ImageIO / AppKit / CoreGraphics 依赖，可在 TestRunner 直接断言。
public struct ClipboardImageRejection: Equatable, Sendable {

    /// 命中的判据
    public enum Kind: Equatable, Sendable {
        /// 宽或高非正（解不出尺寸 / 文件损坏）
        case invalidDimensions
        /// 像素总数超上限（像素炸弹的主判据）
        case pixelCountExceeded
        /// 单边超上限（极长条图：像素总数可能仍很小，但同样会撑爆位图）
        case edgeExceeded
    }

    /// 命中的判据
    public let kind: Kind
    /// 像素宽
    public let width: Int
    /// 像素高
    public let height: Int
    /// 像素总数（尺寸非法时为 0）
    public let pixelCount: Int
    /// 命中的上限值（尺寸非法时为 0）
    public let limit: Int

    public init(kind: Kind, width: Int, height: Int, pixelCount: Int, limit: Int) {
        self.kind = kind
        self.width = width
        self.height = height
        self.pixelCount = pixelCount
        self.limit = limit
    }

    /// 排查用中文描述（logger.debug 口径，不含用户可见文案）
    public var logDescription: String {
        switch kind {
        case .invalidDimensions:
            return "图片尺寸非法（\(width)×\(height)）"
        case .pixelCountExceeded:
            return "图片像素过多（\(width)×\(height) = \(pixelCount) 像素，上限 \(limit)）"
        case .edgeExceeded:
            return "图片单边过长（\(width)×\(height)，单边上限 \(limit)）"
        }
    }

    /// 占位降级文案（卡片 preview，用户能看到「太大所以没存原图」）
    public var placeholderPreview: String {
        switch kind {
        case .invalidDimensions:
            return "图片无法识别（已跳过）"
        case .pixelCountExceeded, .edgeExceeded:
            return "图片 \(width)×\(height)（超过像素上限，未保存原图）"
        }
    }
}

// MARK: - 像素与内存预算

/// 图片像素与内存预算 — 判据的单一来源（Core 纯函数，不依赖 ImageIO / AppKit）
///
/// 背景：ClipboardLimit.maxImageBytes 只限制压缩字节，12000×12000 的纯色 PNG 仅 2.4MB，
/// 但走 NSImage + tiffRepresentation 会瞬间吃满 GB 级内存（实测峰值 2764MB）。
/// 本类型只做算术判定；读头部尺寸由 App 层用 ImageIO 完成（不解码像素）。
public enum ClipboardImagePolicy {

    /// 单张图片允许的最大像素数（64MP：8K 约 33MP、6K 约 24MP 截图仍可用，12000×12000=144MP 被拒）
    public static let maxPixelCount = 64_000_000

    /// 单边最大像素（防 1×1 亿这类极端长条图绕过像素总数判据）
    public static let maxEdgePixels = 32_768

    /// 解码后每像素字节数（RGBA8 口径，用于缓存 cost 与内存估算）
    public static let bytesPerPixel = 4

    /// 缩略图最长边（像素）
    public static let thumbnailMaxEdge = 320

    /// 缩略图缓存预算：按解码后像素字节计费，上限 64MB
    public static let thumbnailCacheCostLimit = 64 * 1024 * 1024

    /// 缩略图缓存条数上限（成本与条数双重约束）
    public static let thumbnailCacheCountLimit = 256

    /// 像素总数（溢出安全：非正尺寸或乘法溢出返回 nil）
    public static func pixelCount(width: Int, height: Int) -> Int? {
        guard width > 0, height > 0 else { return nil }
        let (count, overflow) = width.multipliedReportingOverflow(by: height)
        return overflow ? nil : count
    }

    /// 像素守卫判定
    /// - Parameters:
    ///   - width: 像素宽
    ///   - height: 像素高
    ///   - maxPixelCount: 像素总数上限（≤ 0 时取默认值）
    ///   - maxEdgePixels: 单边上限（≤ 0 时取默认值）
    /// - Returns: 拒绝原因；nil 表示尺寸可用
    public static func rejection(width: Int,
                                 height: Int,
                                 maxPixelCount: Int = maxPixelCount,
                                 maxEdgePixels: Int = maxEdgePixels) -> ClipboardImageRejection? {
        let pixelLimit = maxPixelCount > 0 ? maxPixelCount : Self.maxPixelCount
        let edgeLimit = maxEdgePixels > 0 ? maxEdgePixels : Self.maxEdgePixels
        guard let count = pixelCount(width: width, height: height) else {
            return ClipboardImageRejection(kind: .invalidDimensions,
                                           width: width,
                                           height: height,
                                           pixelCount: 0,
                                           limit: 0)
        }
        guard width <= edgeLimit, height <= edgeLimit else {
            return ClipboardImageRejection(kind: .edgeExceeded,
                                           width: width,
                                           height: height,
                                           pixelCount: count,
                                           limit: edgeLimit)
        }
        guard count <= pixelLimit else {
            return ClipboardImageRejection(kind: .pixelCountExceeded,
                                           width: width,
                                           height: height,
                                           pixelCount: count,
                                           limit: pixelLimit)
        }
        return nil
    }

    /// 尺寸是否可用（拒绝原因见 rejection）
    public static func isAllowed(width: Int, height: Int) -> Bool {
        rejection(width: width, height: height) == nil
    }

    /// 解码后占用的字节数估算（缓存 cost 口径）
    ///
    /// 非正尺寸或非正像素宽度返回 0；乘法溢出返回 Int.max（宁可判为超预算被逐出，也不虚报小值）。
    public static func decodedBytes(width: Int,
                                    height: Int,
                                    bytesPerPixel: Int = bytesPerPixel) -> Int {
        guard width > 0, height > 0, bytesPerPixel > 0 else { return 0 }
        let (count, countOverflow) = width.multipliedReportingOverflow(by: height)
        guard !countOverflow else { return Int.max }
        let (bytes, bytesOverflow) = count.multipliedReportingOverflow(by: bytesPerPixel)
        return bytesOverflow ? Int.max : bytes
    }
}
