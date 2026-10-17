import AppKit
import NetworkMonitorCore

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?
    private var menuBarManager: MenuBarManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppContext.shared.configure(logger: OSLogLogger(category: "App"))
        let coordinator = AppCoordinator()
        self.coordinator = coordinator
        menuBarManager = coordinator.start()
#if DEBUG
        // 仅 DEBUG：设置 NM_SNAPSHOT_DIR 时渲染面板快照并退出（见 MenuPanelSnapshot）
        MenuPanelSnapshot.runIfRequested(repository: coordinator.snapshotClipboardRepository)
#endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.stop()
        AppContext.shared.logger.info("应用退出")
    }
}
