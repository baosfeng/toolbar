import AppKit
import CoreGraphics
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 屏幕录制权限引导

/// 缺屏幕录制权限时的可操作引导 — 不静默失败，直接给出「登记 + 跳转 + 找到包」三步
///
/// 用户口径「系统权限里不支持把我们的 app 放进去，还要到系统应用里去找」的修法就在这一条：
/// 用户点「授权」时先调 `CGRequestScreenCaptureAccess()` —— 这是让应用出现在
/// 「屏幕录制」清单里的唯一途径（从未请求过的应用不会出现在清单里），
/// 再用「在 Finder 中显示」省掉用户自己翻 /Applications 的过程。
@MainActor
enum SnipPermissionGuide {

    /// 系统设置里的屏幕录制面板
    static let screenCaptureSettingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"

    /// 弹出引导
    ///
    /// - Parameters:
    ///   - logger: 日志
    ///   - appPath: 应用包绝对路径（Finder 中显示与手动添加文案共用）
    static func present(logger: LoggingService,
                        appPath: String = Bundle.main.bundleURL.path) {
        logger.warning("缺少屏幕录制权限，弹出引导")
        let alert = NSAlert()
        alert.messageText = "需要「屏幕录制」权限"
        alert.informativeText = """
        截图、取色与窗口检测都需要屏幕录制权限。

        点「授权」会把 \(AppIdentity.displayName) 登记进「系统设置 → 隐私与安全性 → 屏幕录制」并弹一次系统提示；
        回到设置窗勾选后需重启应用才生效。

        若清单里仍没有「\(AppIdentity.displayName)」，点列表下方的 + 手动添加 \(appPath)。
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "授权")
        alert.addButton(withTitle: "在 Finder 中显示")
        alert.addButton(withTitle: "稍后")
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            requestAndOpenSettings(logger: logger)
        case .alertSecondButtonReturn:
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: appPath)])
        default:
            break
        }
    }

    /// 请求屏幕录制权限并打开对应系统设置面板
    ///
    /// `CGRequestScreenCaptureAccess()` 首次调用必返回 false（本次进程拿不到授权），
    /// 它的价值是让系统把本应用列进清单 —— 用户之后在列表里勾选即可。
    static func requestAndOpenSettings(logger: LoggingService) {
        let granted = CGRequestScreenCaptureAccess()
        logger.info("屏幕录制授权请求已发出（本次读数 \(granted ? "已授权" : "未授权")）")
        guard let url = URL(string: screenCaptureSettingsURL) else { return }
        NSWorkspace.shared.open(url)
    }
}
