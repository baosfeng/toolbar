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

    /// 快速保存目录键不在这里：`SnipSaveDirectory.key`（Core，解析时要和落盘规则共用默认目录）
}
