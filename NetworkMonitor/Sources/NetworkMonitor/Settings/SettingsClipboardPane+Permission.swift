import AppKit
import NetworkMonitorCore

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
        accessibilityDot.setColor(granted ? .systemGreen : .systemOrange)
        accessibilityStateLabel.stringValue = granted ? "已授权" : "待授权"
        accessibilityButton.isHidden = granted

        // 文案与色调是 Core 纯规则（ClipboardAccessState），这里只做 API 读取与色值映射
        let access = Self.clipboardAccessState()
        clipboardDot.setColor(Self.color(for: access.tone))
        clipboardStateLabel.stringValue = access.label
        clipboardSettingsButton.isHidden = !access.needsSettingsJump
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

    /// 语义色调 → 状态点颜色（与设置页其余状态点一致）
    private static func color(for tone: ClipboardAccessTone) -> NSColor {
        switch tone {
        case .ok:      return .systemGreen
        case .warning: return .systemOrange
        case .muted:   return .tertiaryLabelColor
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
