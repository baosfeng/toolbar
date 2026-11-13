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

    /// DSH token 用量数据已变化（索引完成、重建完成、降级状态变更）— 订阅方应重新读取快照
    public static let harnessUsageChanged = Notification.Name("AppEvents.harnessUsageChanged")

    /// 发布 DSH token 用量变更通知（线程安全，通常在后台索引队列调用）
    public static func postHarnessUsageChanged() {
        NotificationCenter.default.post(name: harnessUsageChanged, object: nil)
    }

    /// 数值单位风格已变化（设置页「数值单位」切换）— 订阅方应重渲染面板数值
    public static let numberUnitStyleChanged = Notification.Name("AppEvents.numberUnitStyleChanged")

    /// 发布数值单位变更通知（设置页在写存储之后调用）
    public static func postNumberUnitStyleChanged() {
        NotificationCenter.default.post(name: numberUnitStyleChanged, object: nil)
    }

    /// 面板分页可见性 / 顺序已变化（设置页「面板分页」开关、上移、下移）— 面板应重排分段
    ///
    /// 面板若只在自己初始化时读一次偏好，运行中改可见性不会有任何反应（用户口径「设置页禁止了某个功能，
    /// 详情页展开之后没有消失」），因此写存储之后必须发这个事件。
    public static let panelTabsChanged = Notification.Name("AppEvents.panelTabsChanged")

    /// 发布面板分页变更通知（设置页在写存储之后调用）
    public static func postPanelTabsChanged() {
        NotificationCenter.default.post(name: panelTabsChanged, object: nil)
    }

    /// 菜单栏显示偏好已变化（布局 / 数值单位 / 刷新周期 / 密度 / 指标 / 模板）— 菜单栏应重建定时器并重渲染
    public static let menuBarDisplayChanged = Notification.Name("AppEvents.menuBarDisplayChanged")

    /// 发布菜单栏显示偏好变更通知（设置页在写存储之后调用）
    public static func postMenuBarDisplayChanged() {
        NotificationCenter.default.post(name: menuBarDisplayChanged, object: nil)
    }

    /// 剪贴图缩略图已在后台解码完成（增量规格 2.2）— 订阅方只对该哈希命中的可见卡片置重绘
    ///
    /// 通知只在主线程发出（解码回到主线程、写好缓存之后），userInfo 带 `contentHash`：
    /// 卡片流据此定位需要重绘的卡片，不做整片重建、不改选中态。
    public static let clipboardThumbnailReady = Notification.Name("AppEvents.clipboardThumbnailReady")

    /// 缩略图通知里哈希的 userInfo 键
    public static let clipboardThumbnailHashKey = "contentHash"

    /// 发布缩略图就绪通知（主线程调用；hash 为空时不发）
    public static func postClipboardThumbnailReady(contentHash: String) {
        let hash = contentHash.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hash.isEmpty else { return }
        NotificationCenter.default.post(name: clipboardThumbnailReady, object: nil,
                                        userInfo: [clipboardThumbnailHashKey: hash])
    }
}
