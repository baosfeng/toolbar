import Foundation

// MARK: - 截图 / 贴图复制到剪贴板的表示规划

/// 剪贴板图片表示组合的纯判据（不依赖 AppKit，测试可直接断言）
///
/// 背景：`NSImage` 作为剪贴板载体只写**未压缩 TIFF**，全屏 Retina 截图约 22MB，
/// 既超过剪贴板历史 20MB 单图上限（采集端整条静默丢弃），也让其它 App 粘贴时解一张巨图。
/// PNG 始终写（体积小两个数量级），TIFF 只在尺寸不大的时候加一份，兼容只认 TIFF 的老 App。
public enum SnipPasteboardRepresentationPlan {

    /// TIFF 伴随表示的像素上限（超过只写 PNG）
    ///
    /// 未压缩 TIFF 字节 ≈ 像素数 × 4：400 万像素约 15MB，仍在单图上限 20MB 以内；
    /// 全屏 Retina（约 600 万像素）会到 23MB，正是「截图复制后历史里没有」的成因。
    public static let tiffCompanionPixelLimit = 4_000_000

    /// 该尺寸是否需要额外写一份 TIFF（PNG 始终写，不在此判据内）
    /// - Parameters:
    ///   - width: 像素宽
    ///   - height: 像素高
    /// - Returns: true 表示补一份 TIFF 兼容老 App；尺寸异常时返回 true，让编码器自己兜底
    public static func includesTIFFCompanion(width: Int, height: Int) -> Bool {
        guard width > 0, height > 0 else { return true }
        let (pixelCount, overflow) = width.multipliedReportingOverflow(by: height)
        guard !overflow else { return false }
        return pixelCount <= tiffCompanionPixelLimit
    }
}
