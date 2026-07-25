import AppKit

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSUserNotificationCenterDelegate {
    private var menuBarManager: MenuBarManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarManager = MenuBarManager()
        NSUserNotificationCenter.default.delegate = self
    }

    func applicationWillTerminate(_ notification: Notification) {
        ReasonixHookMonitor.cleanupSocket()
        print("👋 应用退出")
    }

    // MARK: - NSUserNotificationCenterDelegate

    /// 应用在前台时也显示通知
    nonisolated func userNotificationCenter(_ center: NSUserNotificationCenter,
                                            shouldPresent notification: NSUserNotification) -> Bool {
        true
    }

    /// 点击通知时打开会话文件
    nonisolated func userNotificationCenter(_ center: NSUserNotificationCenter,
                                            didActivate notification: NSUserNotification) {
        guard let userInfo = notification.userInfo,
              let sessionPath = userInfo["sessionPath"] as? String else { return }
        let url = URL(fileURLWithPath: sessionPath)
        Task { @MainActor in
            NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
        }
    }
}
