import AppKit
import Foundation

/// 系统事件类型
enum EventType: String {
    // 应用事件
    case appOpen = "app_open"
    case appClose = "app_close"
    case appSwitch = "app_switch"
    case windowTitle = "window_title"

    // 屏幕事件
    case screenSleep = "screen_sleep"
    case screenWake = "screen_wake"

    // 系统事件
    case systemSleep = "system_sleep"
    case systemWake = "system_wake"

    // 电源事件（暂未实现，预留）
    case powerAC = "power_ac"
    case powerBattery = "power_battery"

    // 输入事件
    case keyPress = "key_press"

    // 系统采样
    case systemSample = "system_sample"
}

/// 事件监听器：监听系统通知并记录事件到数据库
/// 使用被动通知机制，几乎不消耗 CPU
@MainActor
final class EventMonitor {

    // MARK: - 属性

    private let database: DatabaseManager

    private var currentAppName: String?
    private var currentBundleID: String?

    // MARK: - 初始化

    init(database: DatabaseManager) {
        self.database = database
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - 启动/停止

    /// 开始监听所有系统事件
    func start() {
        let wnc = NSWorkspace.shared.notificationCenter

        // 应用事件
        wnc.addObserver(self, selector: #selector(appLaunched(_:)),   name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        wnc.addObserver(self, selector: #selector(appTerminated(_:)), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        wnc.addObserver(self, selector: #selector(appActivated(_:)),  name: NSWorkspace.didActivateApplicationNotification, object: nil)

        // 屏幕事件
        wnc.addObserver(self, selector: #selector(screenSlept(_:)), name: NSWorkspace.screensDidSleepNotification, object: nil)
        wnc.addObserver(self, selector: #selector(screenWoke(_:)),  name: NSWorkspace.screensDidWakeNotification, object: nil)

        // 系统休眠/唤醒
        wnc.addObserver(self, selector: #selector(systemSlept(_:)), name: NSWorkspace.willSleepNotification, object: nil)
        wnc.addObserver(self, selector: #selector(systemWoke(_:)),  name: NSWorkspace.didWakeNotification, object: nil)

        print("📡 EventMonitor 已启动 — 监听 7 种系统事件")
    }

    /// 停止监听所有系统事件
    func stop() {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - 事件处理

    /// 应用启动
    @objc private func appLaunched(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let name = app.localizedName,
              let bundleID = app.bundleIdentifier
        else { return }

        writeEvent(type: .appOpen, appName: name, bundleID: bundleID)
        print("📱 打开: \(name)")
    }

    /// 应用退出
    @objc private func appTerminated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let name = app.localizedName,
              let bundleID = app.bundleIdentifier
        else { return }

        writeEvent(type: .appClose, appName: name, bundleID: bundleID)
        print("📱 关闭: \(name)")
    }

    /// 应用切换（前台激活）
    @objc private func appActivated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let name = app.localizedName,
              let bundleID = app.bundleIdentifier
        else { return }

        let previousName = currentAppName ?? "（无）"
        currentAppName = name
        currentBundleID = bundleID

        writeEvent(type: .appSwitch, appName: name, bundleID: bundleID)
        print("📱 切换: \(previousName) → \(name)")
    }

    /// 息屏
    @objc private func screenSlept(_ notification: Notification) {
        writeEvent(type: .screenSleep)
        print("💤 屏幕休眠")
    }

    /// 亮屏
    @objc private func screenWoke(_ notification: Notification) {
        writeEvent(type: .screenWake)
        print("☀️ 屏幕唤醒")
    }

    /// 系统休眠
    @objc private func systemSlept(_ notification: Notification) {
        writeEvent(type: .systemSleep)
        print("💤 系统休眠")
    }

    /// 系统唤醒
    @objc private func systemWoke(_ notification: Notification) {
        writeEvent(type: .systemWake)
        print("☀️ 系统唤醒")
    }

    // MARK: - 写入数据库

    /// 记录事件到数据库
    private func writeEvent(
        type: EventType,
        appName: String? = nil,
        bundleID: String? = nil
    ) {
        let timestamp = Date().timeIntervalSince1970
        database.writeEvent(
            type: type,
            appName: appName,
            bundleID: bundleID,
            timestamp: timestamp
        )
    }
}
