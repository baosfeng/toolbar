import Foundation

// MARK: - 截图偏好键名

/// 截图 / 贴图偏好键名 — 从已下线的 `SnipSettingsWindow` 迁出
///
/// 保留 `public` 与既有键值：这些键已被写入用户偏好，改名会让老设置全部失效。
/// SnipController 与该设置页共用同一份定义。
public enum SnipPreferenceKey {
    public static let autoSaveAfterCopy = "snip.autoSaveAfterCopy"
    public static let pinDefaultAlpha = "snip.pinDefaultAlpha"
    public static let annotationColor = "snip.annotationColor"
    public static let annotationLineWidth = "snip.annotationLineWidth"
    /// 标注默认线型：实线 / 虚线（官方专业版「虚线/点线」能力，默认实线）
    public static let annotationDashed = "snip.annotationDashed"
    /// 图片文件贴图时优先显示图像（关闭则直接贴路径文本）
    public static let pinDisplayImageFiles = "snip.pinDisplayImageFiles"
    /// 可被恢复的已关闭贴图数（默认 1，范围 1...10）
    public static let pinRecoverableCount = "snip.pinRecoverableCount"
    /// 输出格式（png / jpeg，缺失按 PNG）
    public static let saveFormat = "snip.saveFormat"
    /// JPEG 质量（0.3…1.0，默认 0.9；仅 jpeg 时生效）
    public static let jpegQuality = "snip.jpegQuality"
    /// OCR 识别成功后是否额外把文字贴到屏幕上（默认关）
    public static let ocrPinResult = "snip.ocrPinResult"

    /// 快速保存目录键不在这里：`SnipSaveDirectory.key`（Core，解析时要和落盘规则共用默认目录）
}
