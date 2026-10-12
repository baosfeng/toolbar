import AppKit
import NetworkMonitorCore

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSUserNotificationCenterDelegate {
    private var coordinator: AppCoordinator?
    private var menuBarManager: MenuBarManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppContext.shared.configure(logger: OSLogLogger(category: "App"))
        let coordinator = AppCoordinator()
        self.coordinator = coordinator
        menuBarManager = coordinator.start()
        NSUserNotificationCenter.default.delegate = self
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.stop()
        AppContext.shared.logger.info("应用退出")
    }

    // MARK: - NSUserNotificationCenterDelegate

    /// 应用在前台时也显示通知
    nonisolated func userNotificationCenter(_ center: NSUserNotificationCenter,
                                            shouldPresent notification: NSUserNotification) -> Bool {
        true
    }

    /// 点击通知时打开 Reasonix 会话文件
    nonisolated func userNotificationCenter(_ center: NSUserNotificationCenter,
                                            didActivate notification: NSUserNotification) {
        guard let userInfo = notification.userInfo,
              let sessionFile = userInfo["sessionFile"] as? String else { return }
        let url = URL(fileURLWithPath: sessionFile)
        Task { @MainActor in
            NSWorkspace.shared.open(url)
        }
    }
}
