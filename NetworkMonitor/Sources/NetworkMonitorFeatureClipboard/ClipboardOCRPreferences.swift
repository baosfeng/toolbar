import Foundation

// MARK: - 图片识别偏好端口

/// 图片文字识别侧需要的偏好面 —— 只取开关一个键（ISP：不与采集偏好混在一起）
///
/// 真实实现在 App 侧一行 conformance，与 ClipboardCapturePreferences 同一处声明。
public protocol ClipboardOCRPreferences: AnyObject, Sendable {

    /// 识别图片中文字开关（关掉后新采集的图片条目不再识别，已有结果保留）
    var imageOCRRecognizeEnabled: Bool { get }
}
