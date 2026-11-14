import Foundation
import UniformTypeIdentifiers

// MARK: - 截图输出格式

/// 截图落盘格式 —— PNG（无损，默认）/ JPEG（体积小，质量可调）
///
/// 判据全收在 Core：偏好里的原始值解析、扩展名、UTType、JPEG 质量夹紧都由这里定义，
/// 落盘实现（`SnipFileWriter`）与设置页只消费，不各写一份口径。
/// 默认 PNG 与既有行为一致（老用户不设置时文件名、格式都不变）。
public enum SnipImageFormat: String, CaseIterable, Equatable, Sendable {
    case png
    case jpeg

    /// JPEG 默认质量（0…1）
    public static let defaultJPEGQuality: Double = 0.9
    /// JPEG 质量的可调范围 —— 低于 0.3 肉眼可见糊，高于 1 无意义
    public static let jpegQualityRange: ClosedRange<Double> = 0.3...1.0

    /// 允许的质量步进（滑块用）
    public static let jpegQualityStep: Double = 0.05

    public var displayName: String {
        switch self {
        case .png: return "PNG"
        case .jpeg: return "JPEG"
        }
    }

    /// 设置页副标题：一句话说明取舍
    public var detailText: String {
        switch self {
        case .png: return "无损，文件较大；文字与线条边缘最锐利"
        case .jpeg: return "有损、体积小；适合发群或邮件，可按质量档权衡"
        }
    }

    /// 文件扩展名（JPEG 固定写 `.jpg`：macOS 与各聊天工具都认，`.jpeg` 只是别名）
    public var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        }
    }

    /// 保存面板与写盘共用的 UTType
    public var contentType: UTType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        }
    }

    /// 偏好原始值 → 格式；缺失或未知一律回落到 PNG（读路径不写回）
    public static func resolved(raw: String?) -> SnipImageFormat {
        guard let raw, let format = SnipImageFormat(rawValue: raw) else { return .png }
        return format
    }

    /// JPEG 质量夹紧到合法区间；非法值（NaN / 越界）回落到默认 0.9
    public static func clampedQuality(_ value: Double) -> Double {
        guard value.isFinite else { return defaultJPEGQuality }
        return min(max(value, jpegQualityRange.lowerBound), jpegQualityRange.upperBound)
    }
}
