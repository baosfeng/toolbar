import AppKit
import NetworkMonitorCore

// MARK: - 屏幕录制权限引导

/// 缺屏幕录制权限时的可操作引导 — 不静默失败，直接给出跳转入口
@MainActor
enum SnipPermissionGuide {

    /// 系统设置里的屏幕录制面板
    static let screenCaptureSettingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"

    static func present(logger: LoggingService) {
        logger.warning("缺少屏幕录制权限，弹出引导")
        let alert = NSAlert()
        alert.messageText = "需要「屏幕录制」权限"
        alert.informativeText = """
        截图、取色与窗口检测都需要屏幕录制权限。

        请在「系统设置 → 隐私与安全性 → 屏幕录制」中勾选 NetworkMonitor，
        然后重启应用（授权后必须重启才生效）。
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn,
              let url = URL(string: screenCaptureSettingsURL) else { return }
        NSWorkspace.shared.open(url)
    }
}
