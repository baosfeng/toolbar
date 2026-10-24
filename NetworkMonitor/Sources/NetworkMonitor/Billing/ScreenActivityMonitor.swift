import AppKit
import CoreGraphics

// MARK: - 屏幕活动监听

/// 屏幕活动监听 — 锁屏 / 显示器休眠 / 系统休眠时通知「不活跃」，解锁或唤醒时通知「活跃」
///
/// 用途：额度后台轮询只在亮屏可用时进行，锁屏和休眠期间不调接口。
/// 监听来源：
/// - `NSWorkspace`：显示器休眠/唤醒、系统休眠/唤醒
/// - `DistributedNotificationCenter`：`com.apple.screenIsLocked` / `Unlocked`（锁屏但未休眠）
@MainActor
final class ScreenActivityMonitor {

    /// 当前是否处于亮屏可用状态
    private(set) var isActive: Bool = true

    /// 状态变化回调（主线程）
    var onChange: ((Bool) -> Void)?

    private var observers: [NSObjectProtocol] = []
    /// 定时自检（通知可能丢失，靠轮询兜底恢复）
    private var watchdog: Timer?

    // MARK: - 生命周期

    /// 开始监听，并以当前锁屏状态初始化
    func start() {
        guard observers.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()

        func observe(_ center: NotificationCenter, _ name: Notification.Name, active: Bool) {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
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

    private func update(active: Bool) {
        guard active != isActive else { return }
        isActive = active
        onChange?(active)
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
}
