import AppKit
import ApplicationServices
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 系统权限中心

/// 三类系统权限的读取与请求 —— 系统 API 的唯一调用点
///
/// 为什么要有它：设置页、面板页脚与截图引导原来各读一次系统 API，口径随时分叉
/// （用户去系统设置勾完回来，界面还停在「待授权」）。现在读与请求都只在这里，
/// UI 一律读 `snapshot`；刷新时机由调用方（`SystemPermissionChain`）统一驱动。
///
/// 读取与请求分开：读取一律静默（不弹系统框），只有用户点「授权」才请求 ——
/// 启动就弹框会让用户以为应用坏了。
@MainActor
final class SystemPermissionCenter {

    /// 三类权限的最新快照
    private(set) var snapshot: SystemPermissionSnapshot = .allUnknown

    private let captureService: any SnipCaptureServicing
    private let logger: LoggingService
    /// 应用包路径（引导文案与「在 Finder 中显示」共用）
    let appPath: String

    init(captureService: any SnipCaptureServicing,
         appPath: String = Bundle.main.bundleURL.path,
         logger: LoggingService = AppContext.shared.logger) {
        self.captureService = captureService
        self.appPath = appPath
        self.logger = logger
    }

    // MARK: 读取

    /// 重新读取三类权限（静默，不弹任何系统框）
    @discardableResult
    func refresh() -> SystemPermissionSnapshot {
        let previous = snapshot
        snapshot = SystemPermissionSnapshot(
            accessibility: Self.probeAccessibility() ? .granted : .pending,
            screenCapture: captureService.isAuthorized() ? .granted : .pending,
            clipboard: Self.probeClipboard())
        // 只为「状态真的变了」记一行：每次窗口切回来都刷日志会把真问题淹掉
        for kind in SystemPermissionKind.allCases
        where previous.state(for: kind) != snapshot.state(for: kind) {
            logger.info("权限状态变化：\(kind.title) \(previous.state(for: kind).label) → "
                        + "\(snapshot.state(for: kind).label)")
        }
        return snapshot
    }

    /// 辅助功能授权态（无 prompt 的静默检查）
    ///
    /// 转发 `PasteStackController` 的实现：Paste Stack 自己也要判断能不能装全局监听，
    /// 两处各写一份选项字典迟早会分叉。
    nonisolated static func probeAccessibility() -> Bool {
        PasteStackController.probeAccessibility()
    }

    /// 剪贴板访问行为 → 权限三态（15.4 起才有该 API，低版本是「未知」）
    static func probeClipboard() -> SystemPermissionState {
        guard #available(macOS 15.4, *) else { return .unknown }
        let access: ClipboardAccessState
        switch NSPasteboard.general.accessBehavior {
        case .alwaysAllow: access = .allowed
        case .alwaysDeny:  access = .denied
        case .ask:         access = .ask
        default:           access = .unspecified
        }
        return SystemPermissionSnapshot.clipboardState(from: access)
    }

    // MARK: 请求（只在用户显式点击时调用）

    /// 请求某一类权限：先让系统登记本应用（把它列进设置清单的唯一途径），再打开对应面板
    func request(_ kind: SystemPermissionKind) {
        switch kind {
        case .accessibility:
            // prompt: true 弹一次系统提示，同时把本应用登记进「辅助功能」清单
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        case .screenCapture:
            // CGRequestScreenCaptureAccess 弹一次提示并让应用出现在「录屏与系统录音」清单；
            // 首次调用必返回 false，用户勾选后必须重启进程才拿得到屏幕内容
            captureService.requestAuthorization()
        case .clipboard:
            // 剪贴板访问行为没有「请求」接口，只能让用户去系统设置改
            break
        }
        logger.info("已请求权限：\(kind.title)")
        openSettings(for: kind)
        refresh()
    }

    /// 打开「系统设置 → 隐私与安全性 → 对应面板」
    func openSettings(for kind: SystemPermissionKind) {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?\(kind.settingsAnchor)"
        guard let url = URL(string: urlString) else {
            logger.warning("系统设置深链无法构造：\(kind.settingsAnchor)")
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// 在 Finder 中显示本应用（用户手动「+」添加时需要自己找到 .app，省掉翻目录这一步）
    func revealAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: appPath)])
    }
}
