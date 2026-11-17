import AppKit
import CoreGraphics
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 屏幕录制权限引导

/// 缺屏幕录制权限时的可操作引导 — 不静默失败，直接给出「登记 + 跳转 + 找到包」三步
///
/// 用户口径「系统权限里不支持把我们的 app 放进去，还要到系统应用里去找」的修法就在这一条：
/// 用户点「授权」时先请求一次 —— 这是让应用出现在「屏幕录制」清单里的唯一途径
/// （从未请求过的应用不会出现在清单里），再用「在 Finder 中显示」省掉翻 /Applications 的过程。
///
/// 深链与 preflight 都不在本文件：URL 只在 `SystemPermissionCenter.openSettings(for:)` 拼一次，
/// 授权判定只走注入的 `SystemPermissionProviding`（与设置页同一份读数，不再是第二份 preflight）。
/// 截图编排（`SnipController`）只调 `presentIfPossible`，不自己判空、不自己拼文案。
@MainActor
enum SnipPermissionGuide {

    /// 权限协议的弱绑定（组合根在启动装配时登记一次）
    ///
    /// 由引导自己持有、而不是让 `SnipController` 多存一个字段：截图编排只管「缺权限时叫一声」，
    /// 真正的读数与深链都在权限中心，绑定关系也就不该散落在编排层。
    private static weak var boundPermissions: (any SystemPermissionProviding)?

    /// 登记权限协议（组合根启动时调用一次）
    static func bind(permissions: any SystemPermissionProviding) {
        boundPermissions = permissions
    }

    /// 缺权限时弹引导；协议还没绑定时只记日志（不静默失败，也不自拼深链）
    static func presentIfNeeded(logger: LoggingService) {
        guard let permissions = boundPermissions else {
            logger.warning("缺少屏幕录制权限，且权限中心尚未装配：本次不弹引导")
            return
        }
        present(permissions: permissions, logger: logger)
    }

    /// 弹出引导
    ///
    /// - Parameters:
    ///   - permissions: 权限协议（深链与「在 Finder 中显示」的唯一出口）
    ///   - logger: 日志
    static func present(permissions: any SystemPermissionProviding,
                        logger: LoggingService) {
        logger.warning("缺少屏幕录制权限，弹出引导")
        let entry = permissions.snapshot.entry(for: .screenCapture)
        let appPath = permissions.appPath
        let alert = NSAlert()
        alert.messageText = "需要「\(entry.title)」权限"
        alert.informativeText = """
        \(entry.detail)

        点「授权」会把 \(AppIdentity.displayName) 登记进「系统设置 → 隐私与安全性 → 屏幕录制」并弹一次系统提示；
        回到设置窗勾选后需重启应用才生效。

        \(entry.manualAddGuide(appPath: appPath))
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "授权")
        alert.addButton(withTitle: "在 Finder 中显示")
        alert.addButton(withTitle: "稍后")
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            permissions.request(.screenCapture)
        case .alertSecondButtonReturn:
            permissions.revealAppInFinder()
        default:
            break
        }
    }
}
