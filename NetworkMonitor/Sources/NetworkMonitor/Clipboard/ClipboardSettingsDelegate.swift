import Foundation
import NetworkMonitorCore
import NetworkMonitorUI

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
    /// 暂停 / 恢复采集（幂等；暂停时采集器停轮询，面板打开也不读剪贴板）
    func settingsDidChangePause(_ paused: Bool)
    /// 按选定时长暂停到某时刻（哨兵值 = 到手动恢复；幂等，已暂停时只改截止时刻）
    func settingsDidChangeTimedPause(until endDate: Date)
    /// 忽略应用清单变更（内部重载忽略集合）
    func settingsDidChangeIgnoredApps()
    /// 图片落盘目录的当前占用（设置页「存储」卡每次刷新现取）
    func settingsClipboardImageUsage() -> ClipboardStorageUsage.Summary
    /// 剪贴板历史总占用字节（正文 UTF-8 + 图片原图；「占用 x / 上限 y」行现取）
    func settingsClipboardTotalUsageBytes() -> UInt64
    /// 请求清空图片存储（内部复用既有清空 + 孤儿清扫，返回删了多少）
    func settingsDidRequestClearImageStorage() -> ClipboardStorageCleanupResult
    /// 最大容量变更（上限调小后立即按新上限清一次，不等到下一次采集）
    func settingsDidChangeMaxBytes()
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
