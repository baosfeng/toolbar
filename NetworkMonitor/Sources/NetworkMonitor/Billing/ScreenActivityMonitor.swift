import AppKit
import CoreGraphics
import NetworkMonitorCore

// MARK: - 屏幕活动监听

/// 屏幕活动监听 — 锁屏 / 显示器休眠 / 系统休眠时通知「不活跃」，解锁或唤醒时通知「活跃」
///
/// 用途：额度后台轮询只在亮屏可用时进行，锁屏和休眠期间不调接口。
/// 监听来源：
/// - `NSWorkspace`：显示器休眠/唤醒、系统休眠/唤醒
/// - `DistributedNotificationCenter`：`com.apple.screenIsLocked` / `Unlocked`（锁屏但未休眠）
///
/// **生命周期硬约束**：本对象必须由组合根持有（`AppCoordinator`）。
/// 通知中心只强持有 observer 闭包（闭包内 `[weak self]`），它自己强持监听器实例；
/// 一旦实例只被局部变量引用，出栈即释放，闭包此后永远拿到 nil —— 额度刷新**再也不会**
/// 暂停或恢复，且没有任何报错（面板停在旧数据）。为此闭包里显式判 nil 并告警，
/// 让这类静默失效在日志里可观测（判据见 ScreenActivityMonitor.reportIfReleased）。
@MainActor
final class ScreenActivityMonitor {

    /// 当前是否处于亮屏可用状态
    private(set) var isActive: Bool = true

    /// 状态变化回调（主线程）
    var onChange: ((Bool) -> Void)?

    private let logger: LoggingService

    private var observers: [NSObjectProtocol] = []
    /// 定时自检（通知可能丢失，靠轮询兜底恢复）
    private var watchdog: Timer?
    /// 状态去重（同一状态的重复投递不重复触发 pause / resume）
    private var relay = ScreenActivityRelay()

    init(logger: LoggingService = AppContext.shared.logger) {
        self.logger = logger
    }

    // MARK: - 生命周期

    /// 开始监听，并以当前锁屏状态初始化
    func start() {
        guard observers.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()

        func observe(_ center: NotificationCenter, _ name: Notification.Name, active: Bool) {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self else {
                    // 自证：闭包还活在通知中心里，监听器却已经不在 —— 只可能是没被持有
                    ScreenActivityMonitor.reportIfReleased(name: name.rawValue)
                    return
                }
                Task { @MainActor [weak self] in
                    self?.update(active: active)
                }
            }
            observers.append(token)
        }

        observe(workspace, NSWorkspace.screensDidSleepNotification, active: false)
        observe(workspace, NSWorkspace.screensDidWakeNotification, active: true)
        observe(workspace, NSWorkspace.willSleepNotification, active: false)
        observe(workspace, NSWorkspace.didWakeNotification, active: true)
        observe(distributed, Notification.Name("com.apple.screenIsLocked"), active: false)
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked"), active: true)

        // 启动时可能已经锁屏（例如开机自启后仍在登录界面）
        update(active: Self.isScreenAvailable())
        startWatchdog()
    }

    /// 停止监听
    func stop() {
        watchdog?.invalidate()
        watchdog = nil
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        for token in observers {
            workspace.removeObserver(token)
            distributed.removeObserver(token)
        }
        observers = []
        relay = ScreenActivityRelay()
    }

    // MARK: - 状态

    /// 30 秒一次的系统状态自检
    ///
    /// 锁屏 / 唤醒通知在休眠唤醒、外接显示器等场景下可能缺失；只靠通知会在「收到休眠、
    /// 却收不到唤醒」时永久停留在暂停态，额度页再也不刷新。自检与事件互为兜底。
    private func startWatchdog() {
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.update(active: Self.isScreenAvailable())
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }

    /// 按去重结果派发暂停 / 恢复
    ///
    /// 同一状态的重复投递（显示器休眠与系统休眠先后到达、自检与通知重叠）只派发一次：
    /// 每次 resume 都会强制拉一轮接口，不去重会把 provider 限流打满。
    private func update(active: Bool) {
        isActive = active
        switch relay.consume(active: active) {
        case .none:
            return
        case .paused:
            logger.info("屏幕活动：进入不可用，额度后台刷新暂停")
            onChange?(false)
        case .resumed:
            logger.info("屏幕活动：恢复可用，额度后台刷新立即刷新一次")
            onChange?(true)
        }
    }

    /// 屏幕当前是否可用（未锁屏且主显示器未休眠）
    private static func isScreenAvailable() -> Bool {
        !isScreenLocked() && CGDisplayIsAsleep(CGMainDisplayID()) == 0
    }

    /// 通过 CGSession 字典判断当前是否锁屏
    private static func isScreenLocked() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (session["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }

    /// 「监听器已被释放」告警（nonisolated：从任意线程的通知回调里调用）
    ///
    /// 静默失效的可观测兜底：日志出现这条即说明装配层没持有监听器，
    /// 额度页会停在旧数据且永不恢复（判别口诀见 docs/踩坑/运行时/监控数据长时间运行后失效.md）。
    nonisolated static func reportIfReleased(name: String) {
        AppContext.shared.logger.warning(
            "屏幕活动监听器已被释放（收到「\(name)」时 self 为空）：组合根未持有它就等于额度刷新永不再暂停/恢复")
    }
}
