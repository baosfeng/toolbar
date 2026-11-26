import AppKit
import NetworkMonitorCore
import NetworkMonitorFeatureClipboard
import NetworkMonitorUI

// MARK: - 权限链路

/// 权限链路 —— 权限中心 + 「读完要同步给谁」的副作用 + 刷新时机，实现 `SystemPermissionProviding`
///
/// 为什么包一层：读完快照还得把辅助功能授权态下发给 Paste Stack（它据此决定要不要装全局 ⌘V
/// 监听），而「什么时候重读」本身也是这条链路的一部分（应用激活 = 用户刚在系统设置勾完回来、
/// 面板打开、设置页点「检测状态」）。把这些收在一处，调用方只调 `refresh()`，
/// 不会出现「某条刷新路径忘了同步」的半截状态。
@MainActor
final class SystemPermissionChain: SystemPermissionProviding {

    /// 真正读系统 API 与发起请求的中心
    let center: SystemPermissionCenter
    /// 辅助功能授权态的下发目标（弱引用：栈的生命周期与组合根同长，不构成环）
    private weak var stack: PasteStackController?
    private let logger: LoggingService
    /// 应用激活观察者（用户从系统设置切回来时重读）
    private var activationObserver: NSObjectProtocol?
    /// 快照订阅者（设置页权限卡等；按 token 退订）
    private var observers: [UUID: (SystemPermissionSnapshot) -> Void] = [:]

    init(center: SystemPermissionCenter,
         stack: PasteStackController?,
         logger: LoggingService = AppContext.shared.logger) {
        self.center = center
        self.stack = stack
        self.logger = logger
        // 中心是唯一的发布点（同步读数、通知异步回调、检测中三处都经它）
        center.onSnapshotChanged = { [weak self] snapshot in
            self?.deliver(snapshot)
        }
        observeActivation()
    }

    isolated deinit {
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
    }

    // MARK: 只读

    var snapshot: SystemPermissionSnapshot { center.snapshot }
    var appPath: String { center.appPath }
    var signingNotice: SigningIdentityNotice? { center.signingNotice }
    /// 读不到签名身份时返回 nil：调用方按 ad-hoc 口径回退（保守写法，不谎称「证书签名」）
    var isCertificateSigned: Bool? { center.signingIdentity?.isCertificateSigned }

    // MARK: 动作

    /// 重读五类权限，并把辅助功能授权态同步给 Paste Stack，最后通知订阅者
    @discardableResult
    func refresh() -> SystemPermissionSnapshot {
        center.refresh()
    }

    /// 检测中 → 异步回填
    func recheck() {
        center.recheck()
    }

    /// 请求一类权限（登记进系统设置清单 + 打开对应面板），随后重读
    func request(_ kind: SystemPermissionKind) {
        center.request(kind)
    }

    /// 打开系统设置（深链唯一出口在中心）
    func openSettings(for kind: SystemPermissionKind) {
        center.openSettings(for: kind)
    }

    /// 在 Finder 中显示应用包
    func revealAppInFinder() {
        center.revealAppInFinder()
    }

    /// 重启应用
    func restartApp() {
        center.restartApp()
    }

    /// 登录项开关（失败时偏好已回滚，返回原因）
    @discardableResult
    func setLoginItemEnabled(_ enabled: Bool) -> String? {
        center.setLoginItemEnabled(enabled)
    }

    // MARK: 订阅

    @discardableResult
    func addObserver(_ handler: @escaping (SystemPermissionSnapshot) -> Void) -> UUID {
        let token = UUID()
        observers[token] = handler
        handler(center.snapshot)
        return token
    }

    func removeObserver(_ token: UUID) {
        observers[token] = nil
    }

    /// 把新快照推给「副作用方 + 全部订阅者」
    private func deliver(_ snapshot: SystemPermissionSnapshot) {
        stack?.syncAccessibility(snapshot.accessibility == .granted)
        for handler in observers.values { handler(snapshot) }
    }

    // MARK: 启动与刷新时机

    /// 启动期：静默读一次 + 登记进 LaunchServices（异步，不阻塞首帧）
    ///
    /// 登记只是 best-effort：实测本应用已在 LaunchServices 库里、系统设置清单里也有它，
    /// 这里补一次是为了「新机器 / 手工拷包」那种确实没登记的场景，失败只记日志。
    func bootstrap() {
        // 先比对签名身份再读权限：提示带要的是「签名变了」与「哪些权限现在没授权」的同一份快照，
        // 顺序反了会先画一帧没有提示带的页面，用户点进系统权限页时反而看不到
        center.reconcileSigningIdentity()
        let snapshot = refresh()
        logger.info("系统权限快照：\(snapshot.summaryLabel)")
        LaunchServicesRegistrar.registerInBackground(appPath: center.appPath, logger: logger)
    }

    /// 应用激活即重读：用户十有八九刚在系统设置里勾完那一下切回来
    ///
    /// 这是「权限都设置好了还显示没权限」的正面修法 —— 辅助功能与剪贴板访问都是即时生效的，
    /// 只要这一刻重读，状态灯无需重启就会变绿。这里不置「检测中」：切回来就闪一下会更像卡住。
    private func observeActivation() {
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
    }
}
