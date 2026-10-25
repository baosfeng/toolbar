import Foundation

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
}
