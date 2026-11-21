import Foundation

// MARK: - 采集偏好端口

/// 采集侧需要的偏好面 —— 采集器 / 粘贴器只依赖这几个键，不感知面板几何与热键
///
/// 为什么立端口：偏好聚合类 ClipboardPreferences 留在 App 层（它还要读面板高度、
/// 热键组合与 UI 目标的几何令牌），服务层不该为了几个键反向依赖 App。
/// 真实实现在 App 侧一行 conformance（extension ClipboardPreferences: ClipboardCapturePreferences {}）。
///
/// 线程模型：实现方须是 Sendable，服务层可从任意线程读取（粘贴器与采集定时器都在主线程）。
public protocol ClipboardCapturePreferences: AnyObject, Sendable {

    /// 采集模式（轮询 / 按需）
    var captureMode: ClipboardCaptureMode { get }

    /// 暂停开关的原始记录（定时暂停到点后仍为 true，真实状态看 isPausedNow）
    var isPaused: Bool { get set }

    /// 定时暂停的截止时刻（时间戳 0 = 暂停到手动恢复）
    var pausedUntil: Date { get set }

    /// 当前是否真的暂停 —— 定时暂停到点自动失效
    var isPausedNow: Bool { get }

    /// 忽略（黑名单）应用的 bundleID 集合
    var ignoredBundleIDs: Set<String> { get }

    /// 最近一次「非本 App」的前台 bundleID（唤起时本 App 在前台则回退到它）
    var lastExternalBundleID: String? { get set }
}
