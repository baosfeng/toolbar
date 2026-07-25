import AppKit

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarManager: MenuBarManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarManager = MenuBarManager()
    }

    func applicationWillTerminate(_ notification: Notification) {
        menuBarManager?.flushBeforeQuit()
        ReasonixHookMonitor.cleanupSocket()
        print("👋 应用退出")
    }
}
