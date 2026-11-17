#if DEBUG
import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 权限页状态取证（仅 DEBUG）

/// 只回放固定快照的权限提供者 —— 让「检测中 / 需重启 / 登录项回滚」这些真实机器上
/// 不一定能凑齐的状态也能出图（真实读数仍由 SystemPermissionCenter 提供，这里只做取证）。
@MainActor
private final class PermissionStateStubProvider: SystemPermissionProviding {

    private(set) var snapshot: SystemPermissionSnapshot
    var appPath: String { "/Applications/\(AppIdentity.displayName).app" }
    private var observers: [UUID: (SystemPermissionSnapshot) -> Void] = [:]

    init(snapshot: SystemPermissionSnapshot) {
        self.snapshot = snapshot
    }

    @discardableResult func refresh() -> SystemPermissionSnapshot { snapshot }
    func recheck() {}
    func request(_ kind: SystemPermissionKind) {}
    func openSettings(for kind: SystemPermissionKind) {}
    func revealAppInFinder() {}
    func restartApp() {}
    @discardableResult func setLoginItemEnabled(_ enabled: Bool) -> String? { nil }

    @discardableResult func addObserver(_ handler: @escaping (SystemPermissionSnapshot) -> Void) -> UUID {
        let token = UUID()
        observers[token] = handler
        handler(snapshot)
        return token
    }
    func removeObserver(_ token: UUID) { observers[token] = nil }
}

/// 权限页状态取证：环境变量 NM_PERMISSION_STATE_SNAPSHOT=1 + NM_SNAPSHOT_DIR=<目录>
///
/// 产出 settings-permissions-{checking,restart}-{light,dark}.png，
/// 补齐「检测中」与「需重启 + 登录项未登记回滚」两种真实机器上凑不齐的状态。
@MainActor
enum SettingsPermissionStateSnapshot {

    static let envKey = "NM_PERMISSION_STATE_SNAPSHOT"

    static var isRequested: Bool {
        ProcessInfo.processInfo.environment[envKey] == "1"
    }

    /// 快照目录（与 MenuPanelSnapshot 读同一个环境变量，路径解析不重复写一份）
    static var requestedDirectory: URL? {
        guard let path = ProcessInfo.processInfo.environment[MenuPanelSnapshot.directoryEnvKey],
              !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// 渲染两种状态（各深浅各一张）
    static func runIfRequested(directory: URL) {
        guard isRequested else { return }
        let states: [(String, SystemPermissionSnapshot)] = [
            ("checking", .allChecking),
            ("restart", SystemPermissionSnapshot(accessibility: .granted,
                                                 screenCapture: .granted,
                                                 clipboard: .pending,
                                                 notification: .denied,
                                                 loginItem: .unregistered,
                                                 loginItemRollbackReason: "系统拒绝登记")),
        ]
        for (name, snapshot) in states {
            let provider = PermissionStateStubProvider(snapshot: snapshot)
            let window = SettingsWindow(factories: [
                .permissions: { SettingsPermissionPane(permissions: provider) },
            ])
            guard let view = window.prepareForSnapshot(.permissions) else { continue }
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let suffix = appearance == .aqua ? "light" : "dark"
                let url = directory.appendingPathComponent("settings-permissions-\(name)-\(suffix).png")
                MenuPanelSnapshot.render(view: view, size: SettingsTheme.windowSize,
                                         appearanceName: appearance, to: url)
            }
        }
    }
}
#endif