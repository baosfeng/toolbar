import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 剪贴板设置页（权限）

/// 权限状态与跳转 — 从主文件拆出：主文件要腾出空间放「存储」卡
///
/// 跨文件访问：`clipboardDot` / `clipboardStateLabel` / `clipboardSettingsButton` /
/// `accessibilityDot` / `accessibilityStateLabel` / `accessibilityButton` 与
/// `settingsDelegate` 由 private 放宽为 internal，仅供本扩展使用。
extension SettingsClipboardPane {

    /// 权限状态：无权限时必须显式呈现并提供跳转（不得静默失败）
    func refreshPermissionStatus() {
        let granted = settingsDelegate?.settingsAccessibilityGranted() ?? false
        accessibilityDot.setColor(granted ? SettingsTheme.okInk : SettingsTheme.warnInk)
        accessibilityStateLabel.stringValue = granted ? "已授权" : "待授权"
        accessibilityButton.isHidden = granted

        // 文案与色调是 Core 纯规则（ClipboardAccessState），这里只做 API 读取与色值映射
        let access = Self.clipboardAccessState()
        clipboardDot.setColor(SettingsTheme.statusDotColor(Self.statusTone(for: access.tone)))
        clipboardStateLabel.stringValue = access.label
        clipboardSettingsButton.isHidden = !access.needsSettingsJump
    }

    /// 页头胶囊：剪贴板访问授权态 + 图片文件数
    ///
    /// 为什么是「文件数」而不是契约示例里的「条目数」：历史条目数只在组合根的数据库里，
    /// 设置页没有同步读数（`ClipboardSettingsDelegate` 只暴露图片目录占用）；
    /// 图片文件数是本页「存储」卡同一个读数，口径一致且不新开数据源。
    /// 文案写「文件」而不是「条」，避免与实际条目口径对不上。
    func refreshHeaderChip(usage: ClipboardStorageUsage.Summary) {
        let access = Self.clipboardAccessState()
        page.setStatusChip(SettingsStatusChip(subject: access.label,
                                              detail: "\(usage.fileCount) 个文件",
                                              tone: Self.statusTone(for: access.tone)))
    }

    // MARK: 权限映射

    /// 读取系统剪贴板访问行为（15.4+ 才有该 API，低版本返回未知）
    private static func clipboardAccessState() -> ClipboardAccessState {
        if #available(macOS 15.4, *) {
            switch NSPasteboard.general.accessBehavior {
            case .alwaysAllow: return .allowed
            case .alwaysDeny:  return .denied
            case .ask:         return .ask
            default:           return .unspecified
            }
        }
        return .unknown
    }

    /// Core 的三档色调 → 设置页胶囊 / 状态点的三档语义（一处映射，两处显示不各判一遍）
    private static func statusTone(for tone: ClipboardAccessTone) -> SettingsStatusTone {
        switch tone {
        case .ok:      return .ok
        case .warning: return .warn
        case .muted:   return .muted
        }
    }

    // MARK: 动作

    @objc func requestAccessibility() {
        settingsDelegate?.settingsDidRequestAccessibilityPermission()
        refreshPermissionStatus()
    }

    @objc func requestClipboardAccess() {
        settingsDelegate?.settingsDidRequestClipboardSettings()
    }
}
