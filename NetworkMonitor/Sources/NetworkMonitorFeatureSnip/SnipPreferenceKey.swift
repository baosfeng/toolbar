import Foundation

// MARK: - 截图偏好键名

/// 截图 / 贴图偏好键名 — 从已下线的 `SnipSettingsWindow` 迁出
///
/// 保留 `public` 与既有键值：这些键已被写入用户偏好，改名会让老设置全部失效。
/// 截图编排（App）与该设置页共用同一份定义，现在两边都 import 这个功能层。
public enum SnipPreferenceKey {
    public static let autoSaveAfterCopy = "snip.autoSaveAfterCopy"
    /// 贴图默认透明度的键不在这里：PinDefaultAlphaPreferenceKey.pinDefaultAlpha（Core，与钳制规则同处，消费方共用）
    public static let annotationColor = "snip.annotationColor"
    public static let annotationLineWidth = "snip.annotationLineWidth"
    /// 标注默认线型：实线 / 虚线（官方专业版「虚线/点线」能力，默认实线）
    public static let annotationDashed = "snip.annotationDashed"
    /// 文字标注字号（缺键 = 沿用旧口径「由线宽推导」，老偏好零迁移）
    public static let annotationTextFontSize = "snip.annotation.textFontSize"
    /// 文字标注是否加粗
    public static let annotationTextBold = "snip.annotation.textBold"
    /// 文字标注字体族（SnipTextFamily 的 rawValue）
    public static let annotationTextFamily = "snip.annotation.textFamily"
    /// 马赛克块边长（像素，2…32；缺键 = 14，与 SnipMosaicProcessor 的既有常量一致）
    public static let annotationMosaicBlock = "snip.annotation.mosaicBlock"
    /// 高斯模糊半径（像素，1…40；缺键 = 14）
    public static let annotationBlurRadius = "snip.annotation.blurRadius"
    /// 截图里是否用滚轮调数值（缺键 = 开）
    ///
    /// 滚轮一旦被我们塞进三四种语义（调粗细 / 调透明度 / 缩放图形 / 调放大镜），
    /// 就必须给一条整体关闭的通路——否则习惯用滚轮做别的操作的用户只能忍。
    /// 官方也有同款开关（`disable_mouse_scroll`，issue #2607 就是用户在找它）。
    public static let scrollAdjustEnabled = "snip.scrollAdjustEnabled"
    /// 是否已经展示过标注操作提示（缺键 = 没看过；看过就不再打扰）
    public static let annotationHintsShown = "snip.annotation.hintsShown"
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
