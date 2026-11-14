import Foundation
import NetworkMonitorCore

// MARK: - 剪贴板设置事件回调

/// 剪贴板设置页需要宿主实现的动作 — 热键注册、采集器重启、权限跳转
///
/// 定义从 `ClipboardSettingsWindow` 迁出：旧窗口下线后协议仍被设置页使用，
/// 由组合根（`AppCoordinator`）实现，页面只依赖协议。
@MainActor
protocol ClipboardSettingsDelegate: AnyObject {
    /// 热键变更 — 返回是否注册成功（false 时页面标冲突并保留原组合键）
    func settingsDidChangeHotKey(_ combo: HotKeyCombo) -> Bool
    /// 采集模式变更（内部按需重启采集器）
    func settingsDidChangeCaptureMode()
    /// 忽略应用清单变更（内部重载忽略集合）
    func settingsDidChangeIgnoredApps()
    /// 当前是否已获得辅助功能权限
    func settingsAccessibilityGranted() -> Bool
    /// 请求跳转系统设置的辅助功能授权页
    func settingsDidRequestAccessibilityPermission()
    /// 请求打开剪贴板相关系统设置（剪贴板访问权限）
    func settingsDidRequestClipboardSettings()
    /// 图片落盘目录的当前占用（设置页「存储」卡每次刷新现取）
    func settingsClipboardImageUsage() -> ClipboardStorageUsage.Summary
    /// 请求清空图片存储（内部复用既有清空 + 孤儿清扫，返回删了多少）
    func settingsDidRequestClearImageStorage() -> ClipboardStorageCleanupResult
}

// MARK: - 清空结果

/// 清空图片存储的结果 — 设置页据此给出「删了多少」的可见反馈，不静默
struct ClipboardStorageCleanupResult: Equatable, Sendable {
    /// 被删除的历史条目数（收藏项保留）
    let deletedItems: Int
    /// 被删除的残留图片文件数（原图 + 缩略图）
    let removedFiles: Int

    /// 是否什么都没删（设置页据此说明「本来就没有可清理的内容」）
    var isNoop: Bool { deletedItems == 0 && removedFiles == 0 }
}
