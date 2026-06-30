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
            button.action = #selector(statusItemClicked)
            button.target = self
        }

        // 构建菜单
        let menu = NSMenu()
        menu.addItem(buildTitleItem())
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "今日概览", action: #selector(showTodaySummary), keyEquivalent: "1"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "开机自启", action: #selector(toggleLaunchAtLogin), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))

        item.menu = menu
    }

    /// 标题栏项目（显示版本信息）
    private func buildTitleItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: "📊  macMonitor  v0.1.0",
            action: nil,
            keyEquivalent: ""
        )
        item.isEnabled = false
        return item
    }

    // MARK: - 操作

    @objc private func statusItemClicked() {
        // 点击图标时的操作（菜单已自动弹出）
    }

    @objc private func showTodaySummary() {
        print("显示今日概览（待实现）")
    }

    @objc private func toggleLaunchAtLogin() {
        print("开机自启切换（待实现）")
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
