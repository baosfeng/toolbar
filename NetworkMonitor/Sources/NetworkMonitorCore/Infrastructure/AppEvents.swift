import Foundation

// MARK: - 应用事件总线

/// 应用级事件通知 — 数据变更后发布，UI 层订阅以即时刷新
///
/// 基于 `NotificationCenter` 的轻量事件总线：
/// - 发布可在任意线程调用（如后台事件队列）
/// - 订阅方通过 `queue: .main` 或 `Task { @MainActor }` 回到主线程更新 UI
/// - 事件名集中定义，避免散落的字符串
public enum AppEvents {
    /// 剪贴板历史已变化（新采集落库、收藏、删除、清空、Paste Stack 推进）— 订阅方应立即刷新面板
    public static let clipboardChanged = Notification.Name("AppEvents.clipboardChanged")

    /// 发布剪贴板历史变更通知（线程安全，可任意队列调用）
    public static func postClipboardChanged() {
        NotificationCenter.default.post(name: clipboardChanged, object: nil)
    }
}
