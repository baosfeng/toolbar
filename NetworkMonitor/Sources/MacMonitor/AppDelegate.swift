import AppKit
import Foundation

/// 应用委托：管理应用生命周期、菜单栏初始化和权限检查
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - 属性

    private var statusItem: NSStatusItem?
    private let databaseManager = DatabaseManager()
    private var eventMonitor: EventMonitor?
    private var keyPressMonitor: KeyPressMonitor?
    private var systemSampler: SystemSampler?
    private lazy var statsProvider = StatsProvider(database: databaseManager)
    private lazy var menuBuilder = MenuBuilder(statsProvider: statsProvider)

    // MARK: - 应用生命周期

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 初始化数据库
        databaseManager.initialize()

        // 启动事件监听
        let monitor = EventMonitor(database: databaseManager)
        monitor.start()
        eventMonitor = monitor

        // 启动击键监听
        let keyMonitor = KeyPressMonitor(database: databaseManager)
        if keyMonitor.start() {
            keyPressMonitor = keyMonitor
        }

        // 启动系统采样
        let sampler = SystemSampler(database: databaseManager)
        sampler.start()
        systemSampler = sampler

        // 设置菜单栏
        setupMenuBar()

        print("macMonitor 已启动 — 数据目录: \(databaseManager.dbPath)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        systemSampler?.stop()
        keyPressMonitor?.stop()
        eventMonitor?.stop()
        databaseManager.close()
    }

    // MARK: - 菜单栏

    /// 初始化菜单栏图标和下拉菜单
    private func setupMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        // 图标按钮
        if let button = item.button {
            button.title = "📊"
        }

        // 使用 MenuBuilder 构建初始菜单
        item.menu = buildFreshMenu()
    }

    /// 构建最新数据的菜单
    private func buildFreshMenu() -> NSMenu {
        let menu = menuBuilder.buildMenu()
        menu.delegate = self
        return menu
    }

    // MARK: - 操作

    @objc func showDailyReport() {
        print("查看每日报告（待实现）")
    }

    @objc func showWeeklyReport() {
        print("查看每周报告（待实现）")
    }

    @objc func toggleLaunchAtLogin() {
        print("开机自启切换（待实现）")
    }

    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - NSMenuDelegate

extension AppDelegate: NSMenuDelegate {

    /// 菜单即将打开时重新构建，确保数据显示最新
    func menuWillOpen(_ menu: NSMenu) {
        statusItem?.menu = buildFreshMenu()
    }
}
