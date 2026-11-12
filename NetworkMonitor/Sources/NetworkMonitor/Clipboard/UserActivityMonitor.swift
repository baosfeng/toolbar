import AppKit
import CoreGraphics

// MARK: - 用户活跃度探针

/// 用户活跃度探针（增量 B）
///
/// 只读 `CGEventSource.secondsSinceLastEventType(.combinedSessionState, .null)`：
/// 这是免授权的公开 API——不申请「输入监控」权限、不安装 EventTap、不读取任何按键内容，
/// 只拿「距最近一次输入事件过了多少秒」这一个时间差。
/// App 前台状态由 NSWorkspace 的应用激活 / 退场通知维护，避免每次 tick 再查 frontmostApplication。
@MainActor
final class UserActivityMonitor {

    /// 距最近一次用户输入（键盘 / 鼠标 / 滚轮 / 触控板等 bundled 事件）的秒数
    ///
    /// 查询失败时系统返回 0（按「刚活跃」处理，走最快档，不漏采）。
    var idleSeconds: TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .null)
    }

    /// 本 App 是否在最前台（由通知缓存；缓存缺失时现场查一次）
    var isAppActive: Bool {
        guard let cached = cachedIsAppActive else {
            return Self.isForegroundApplicationOwn(NSWorkspace.shared.frontmostApplication)
        }
        return cached
    }

    private var cachedIsAppActive: Bool?
    private var observers: [NSObjectProtocol] = []

    init() {
        // 只做一次前台状态采样；观察者由采集器 start() 时才注册（按需模式不常驻任何监听）
        cachedIsAppActive = Self.isForegroundApplicationOwn(NSWorkspace.shared.frontmostApplication)
    }

    // MARK: 观察者生命周期

    /// 开始监听前台状态变化（幂等：已注册时不重复注册）
    func start() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [NSWorkspace.didActivateApplicationNotification,
                                          NSWorkspace.didDeactivateApplicationNotification,
                                          NSWorkspace.didHideApplicationNotification,
                                          NSWorkspace.didLaunchApplicationNotification]
        for name in names {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // 通知回调可能在非主队列上下文：统一回主线程再改状态
                Task { @MainActor in self?.refreshFrontmostState() }
            }
            observers.append(observer)
        }
    }

    /// 停止监听（幂等）；不注销的话 App 退出前会一直持有闭包，属于资源泄漏
    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        for observer in observers {
            center.removeObserver(observer)
        }
        observers.removeAll()
    }

    // isolated deinit：注销 NSWorkspace 观察者必须在主线程（通知中心自身的线程要求）
    isolated deinit {
        stop()
    }

    // MARK: 前台判定

    private func refreshFrontmostState() {
        cachedIsAppActive = Self.isForegroundApplicationOwn(NSWorkspace.shared.frontmostApplication)
    }

    /// 前台是否是本 App
    ///
    /// 未打包运行（`swift run`，bundleIdentifier 为空）时无法比对，按「活跃」处理，
    /// 避免开发态一律落最慢档导致采集延迟；frontmost 缺失时按非前台处理。
    private static func isForegroundApplicationOwn(_ application: NSRunningApplication?) -> Bool {
        guard let application else { return false }
        guard let ownBundleID = Bundle.main.bundleIdentifier else { return true }
        return application.bundleIdentifier == ownBundleID
    }
}
