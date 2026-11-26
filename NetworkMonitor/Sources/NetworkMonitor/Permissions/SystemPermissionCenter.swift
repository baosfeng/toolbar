import AppKit
import ApplicationServices
import NetworkMonitorCore
import NetworkMonitorFeatureClipboard
import NetworkMonitorUI

// MARK: - 系统权限中心

/// 五类系统权限的读取、请求与深链 —— 系统 API 与 `x-apple.systempreferences:` 的唯一调用点
///
/// 为什么要有它：设置页、功能页就地入口、面板页脚与截图引导原来各读一次系统 API、
/// 各拼一条深链，口径随时分叉（用户去系统设置勾完回来，界面还停在「待授权」）。
/// 现在读与请求都只在这里，UI 一律读 `snapshot`；刷新时机由调用方（`SystemPermissionChain`）统一驱动。
///
/// 读取与请求分开：读取一律静默（不弹系统框），只有用户点「授权」才请求 ——
/// 启动就弹框会让用户以为应用坏了。
///
/// 通知授权是异步 API（`UNUserNotificationCenter.getNotificationSettings`）：这里只读
/// `NotificationServicing` 缓存的那一份（它自己是唯一异步读取点），并在它的
/// `onAuthorizationChanged` 回调里重发快照 —— 主线程不会为一次读数阻塞。
@MainActor
final class SystemPermissionCenter {

    /// 五类权限的最新快照
    private(set) var snapshot: SystemPermissionSnapshot = .allUnknown
    /// 快照变化回调（链路据此同步副作用并通知 UI）
    var onSnapshotChanged: ((SystemPermissionSnapshot) -> Void)?
    /// 签名身份变化提示回调（权限页据此决定提示带显隐；首启动不触发）
    var onSigningNoticeChanged: ((SigningIdentityNotice?) -> Void)?

    private let captureService: any SnipCaptureServicing
    private let notifications: any NotificationServicing
    private let launchAtStartup: LaunchAtStartupService
    private let logger: LoggingService
    /// 上次启动的签名身份（判「是不是升级换身份导致授权失配」的唯一历史来源）
    private let signingHistory: SigningIdentityPreferences
    /// 本次启动读到的签名身份（nil = 读不到，此时不比较、不提示）
    private(set) var signingIdentity: SigningIdentity?
    /// 签名身份变化提示（只在启动期比对成功且真变了时非 nil）
    private(set) var signingNotice: SigningIdentityNotice?
    /// 应用包路径（引导文案与「在 Finder 中显示」共用）
    let appPath: String
    /// 登录项最近一次注册失败的回滚说明（显示在卡下警示句里）
    private var loginItemRollbackReason: String?
    /// 通知授权的最新缓存值（回调写入，读取路径只读它，不阻塞主线程）
    private var notificationState: SystemPermissionState

    init(captureService: any SnipCaptureServicing,
         notifications: any NotificationServicing,
         launchAtStartup: LaunchAtStartupService = LaunchAtStartupService(),
         appPath: String = Bundle.main.bundleURL.path,
         signingHistory: SigningIdentityPreferences = SigningIdentityPreferences(storage: AppContext.shared.storage),
         logger: LoggingService = AppContext.shared.logger) {
        self.captureService = captureService
        self.notifications = notifications
        self.launchAtStartup = launchAtStartup
        self.appPath = appPath
        self.signingHistory = signingHistory
        self.logger = logger
        self.notificationState = SystemPermissionSnapshot
            .notificationState(from: notifications.authorizationState)
        // 通知授权只有异步回调这一条回填路径：中心接管它，回调到达时重发快照
        notifications.onAuthorizationChanged = { [weak self] authorization in
            guard let self else { return }
            self.notificationState = SystemPermissionSnapshot.notificationState(from: authorization)
            self.publish(self.readSnapshot())
        }
    }

    // MARK: 读取

    /// 重新读取五类权限（静默，不弹任何系统框）
    ///
    /// 通知一项读的是缓存（见类注释）；要拿最新的通知授权态用 `recheck()`。
    @discardableResult
    func refresh() -> SystemPermissionSnapshot {
        let snapshot = readSnapshot()
        publish(snapshot)
        return snapshot
    }

    /// 读当前签名身份并与上次记录比对（启动期调用一次，幂等）
    ///
    /// 为什么只在启动期做：签名身份在一次进程生命周期里不会变（TCC 也是按进程启动时
    /// 读到的 CDHash 判的），每次刷新都读一遍 SecCode 纯属浪费；而「变了」这件事
    /// 只在「新包第一次启动」那一瞬有意义。
    ///
    /// 读不到签名身份（未打包的 swift run）时什么都不做：不写历史、不造提示，
    /// 否则下次启动会把「读不到」当成一次真实变化。
    func reconcileSigningIdentity() {
        guard let identity = SigningIdentityReader.current(logger: logger) else { return }
        signingIdentity = identity
        signingNotice = signingHistory.reconcile(current: identity)
        if let notice = signingNotice {
            logger.warning("签名身份已变化（\(notice.identity.kind.rawValue)）："
                           + "已授权项可能全部失配，需在系统权限页重新确认")
        } else {
            logger.info("签名身份：\(identity.kind.rawValue)（与上次记录一致或首启动）")
        }
        onSigningNoticeChanged?(signingNotice)
        refresh()
    }

    /// 检测中 → 异步回填：先把五行置「检测中」，再等通知授权回调回来填真值
    ///
    /// 四类同步读数在回调里一并重读；若通知回调迟迟不到（系统异常），
    /// 600ms 后按缓存回填一次，避免界面永远停在「检测中」。
    func recheck() {
        publish(.allChecking)
        notifications.refreshAuthorizationState()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            if snapshot == .allChecking { publish(readSnapshot()) }
        }
    }

    /// 组装快照（唯一真源）
    private func readSnapshot() -> SystemPermissionSnapshot {
        SystemPermissionSnapshot(
            accessibility: Self.probeAccessibility() ? .granted : .pending,
            screenCapture: captureService.isAuthorized() ? .granted : .pending,
            clipboard: Self.probeClipboard(),
            notification: notificationState,
            loginItem: SystemPermissionSnapshot.loginItemState(from: launchAtStartup.registration),
            loginItemRollbackReason: loginItemRollbackReason)
    }

    /// 发布快照：只为「状态真的变了」记一行日志，再把新快照交给链路
    private func publish(_ snapshot: SystemPermissionSnapshot) {
        let previous = self.snapshot
        self.snapshot = snapshot
        for kind in SystemPermissionKind.allCases
        where previous.state(for: kind) != snapshot.state(for: kind) {
            logger.info("权限状态变化：\(kind.title) \(previous.state(for: kind).label) → "
                        + "\(snapshot.state(for: kind).label)")
        }
        onSnapshotChanged?(snapshot)
    }

    /// 辅助功能授权态（无 prompt 的静默检查）
    ///
    /// 转发 `PasteStackController` 的实现：Paste Stack 自己也要判断能不能装全局监听，
    /// 两处各写一份选项字典迟早会分叉。
    nonisolated static func probeAccessibility() -> Bool {
        PasteStackController.probeAccessibility()
    }

    /// 剪贴板访问行为 → 权限状态（15.4 起才有该 API，低版本是「未知」）
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

    /// 通知授权态（读 `NotificationServicing` 的缓存值，不阻塞主线程）
    func probeNotifications() -> SystemPermissionState {
        notificationState
    }

    /// 登录项登记态（走 `SMAppService.mainApp.status` 的四档翻译，只此一份）
    func probeLoginItem() -> SystemPermissionState {
        SystemPermissionSnapshot.loginItemState(from: launchAtStartup.registration)
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
        case .notification:
            // requestAuthorization 是异步的，结果经 onAuthorizationChanged 回调回到中心
            notifications.requestAuthorization()
        case .loginItem:
            // 登录项不在「请求」语义里：注册失败要回滚偏好，见 setLoginItemEnabled
            setLoginItemEnabled(true)
        }
        logger.info("已请求权限：\(kind.title)")
        openSettings(for: kind)
        refresh()
    }

    /// 登录项开关（唯一入口：写偏好 + 注册，失败回滚并记下原因）
    ///
    /// - Returns: 回滚说明（nil = 成功）
    @discardableResult
    func setLoginItemEnabled(_ enabled: Bool) -> String? {
        let success = launchAtStartup.setEnabled(enabled)
        if success {
            loginItemRollbackReason = nil
        } else {
            let reason = launchAtStartup.lastFailureReason ?? "系统未允许"
            loginItemRollbackReason = reason
            logger.error("开机自启动切换失败，已回滚：\(reason)")
        }
        refresh()
        return success ? nil : loginItemRollbackReason
    }

    // MARK: 深链（唯一出口）

    /// 打开「系统设置」里对应的面板 —— 全仓唯一一处 `x-apple.systempreferences:` 字面量
    ///
    /// 三类隐私面板接在「隐私与安全性」之后（`?<锚点>`）；
    /// 通知与登录项是独立的设置扩展面板 id（实测 `/System/Library/ExtensionKit/Extensions/`
    /// 下的 LoginItems.appex / NotificationsSettings.appex，bundle id 与本表一致）。
    func openSettings(for kind: SystemPermissionKind) {
        let scheme = "x-apple.systempreferences:com.apple.preference.security"
        let urlString = kind.anchorsPrivacyPane
            ? "\(scheme)?\(kind.settingsAnchor)"
            : "x-apple.systempreferences:\(kind.settingsAnchor)"
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

    /// 重启应用（屏幕录制授权后 TCC 只在进程启动时重新读取）
    ///
    /// 不做自我重启：自签名包重新拉起会打断用户的当前工作，交给用户手动打开即可。
    func restartApp() {
        logger.info("用户请求重启应用（屏幕录制授权生效需要）")
        NSApp.terminate(nil)
    }
}
