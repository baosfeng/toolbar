import AppKit
import NetworkMonitorCore

// MARK: - 采集服务实现

/// 剪贴板采集器 — 同一个实现的两种模式（设计规格第 6 节分支 A / B）
///
/// - 模式 B（polling，默认）：动态间隔 Timer 轮询 + changeCount 变更即读；间隔由 `ClipboardPollSchedule`
///   给出（0.5 / 2 / 5s 随活跃度切换），另有 `com.apple.pasteboard.changed` 通知提前唤醒一次 capture
/// - 模式 A（onDemand）：不启动轮询，仅在打开面板或点击「采集当前剪贴板」时调 captureNow()
///
/// 两种模式共用同一条流水线：changeCount 判定 → 访问权限判定 → 忽略判定 → 哈希 → 落盘 → onCapture。
/// 落库与事件通知由调用方（组合根）在 onCapture 回调里完成，采集器不直接触碰仓储。
@MainActor
public final class PasteboardWatcher: ClipboardCaptureService {

    /// 活跃档间隔（最快档；实际间隔由 `ClipboardPollSchedule` 逐次计算，本常量供测试与既有断言使用）
    static let pollInterval: TimeInterval = ClipboardPollSchedule.activeInterval

    /// 剪贴板变更的分布式通知名（只作提前唤醒；changeCount 仍是唯一准入闸门）
    static let pasteboardChangedNotification = Notification.Name("com.apple.pasteboard.changed")

    /// 偏好端口（不依赖 App 的具体偏好类）：暂停扩展在同 target 内读写暂停键
    let preferences: any ClipboardCapturePreferences
    /// internal：图片后台结算在 PasteboardWatcher+Images.swift（跨文件访问，同目录内无其他调用方）
    let logger: LoggingService
    /// 放宽为 internal：PasteboardWatcher+Images.swift 的解析逻辑要读
    let pasteboard: NSPasteboard
    /// 用户活跃度探针（免权限读秒 + 前台状态缓存）
    private let activityMonitor: UserActivityMonitor
    /// 提前唤醒的通知观察者（stop() 时注销）
    private var wakeObserver: NSObjectProtocol?

    /// 下一次 tick 的一次性 Timer（每次 tick 后按当前档位重排，不重建 RunLoop 源）
    private var timer: Timer?
    /// 上次读到的 changeCount；初值取哨兵值，避免在初始化阶段读取剪贴板（探针未覆盖的路径不做多余访问）
    private var lastChangeCount = Int.min

    public private(set) var isRunning = false
    public var onStateChange: ((ClipboardCaptureState) -> Void)?
    public var onCapture: ((ClipboardDraft) -> Void)?

    /// 日志一律由调用方显式注入（功能层不取 AppContext.shared）
    public init(preferences: any ClipboardCapturePreferences,
                logger: LoggingService,
                pasteboard: NSPasteboard = .general,
                activityMonitor: UserActivityMonitor? = nil) {
        self.preferences = preferences
        self.logger = logger
        self.pasteboard = pasteboard
        self.activityMonitor = activityMonitor ?? UserActivityMonitor()
    }

    // MARK: ClipboardCaptureService

    public func start() {
        guard !isRunning else { return }
        // 暂停中不重启轮询（恢复走 resume()）：启动时偏好为暂停，据此保持暂停态并明确上报
        guard !isPaused else { onStateChange?(.paused); return }
        guard preferences.captureMode == .polling else {
            // 分支 A：不轮询，退化为「打开面板读一次 + 面板内手动采集」
            logger.info("剪贴板采集启动：分支 A（按需），不启动后台轮询")
            onStateChange?(.stopped)
            return
        }
        guard checkAccessBehavior() else { return }

        isRunning = true
        activityMonitor.start()
        registerWakeObserver()
        scheduleTick()
        onStateChange?(.running)
        logger.info("剪贴板采集启动：分支 B（动态轮询 " + Self.secondsText(ClipboardPollSchedule.activeInterval)
                   + "–" + Self.secondsText(ClipboardPollSchedule.idleInterval) + "s）")
    }

    public func stop() {
        // 先落 isRunning = false：重排决策依赖它，迟到的一次性 Timer 不会再排下一次
        let wasRunning = isRunning
        isRunning = false
        timer?.invalidate()
        timer = nil
        unregisterWakeObserver()
        activityMonitor.stop()
        // 未运行时只是「清理已泄漏的观察者」，不发状态事件（保持原有静默语义）
        guard wasRunning else { return }
        onStateChange?(.stopped)
        logger.info("剪贴板采集已停止")
    }

    // deinit 与 @MainActor 隔离（Swift 6 isolated deinit）：Timer 失效与观察者摘除都在主线程上做，
    // 避免跨线程碰 Timer 这类非 Sendable 资源；即便调用方忘了 stop()，析构时也会自动收口。
    isolated deinit {
        timer?.invalidate()
        if let wakeObserver {
            DistributedNotificationCenter.default().removeObserver(wakeObserver)
        }
    }

    // MARK: 动态轮询

    /// 按当前档位排下一次一次性 tick（停止后永不重排）
    private func scheduleTick() {
        timer?.invalidate()
        timer = nil
        let idleSeconds = activityMonitor.idleSeconds
        let isAppActive = activityMonitor.isAppActive
        guard let interval = ClipboardPollSchedule.nextInterval(isRunning: isRunning,
                                                               idleSeconds: idleSeconds,
                                                               isAppActive: isAppActive) else {
            return
        }
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        // 加入 RunLoop 的 common modes：菜单展开 / 拖拽期间也不停止采集
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// 一次 tick：采集一次 + 按新的活跃度重排下一次
    private func tick() {
        guard isRunning else { return }
        capture()
        scheduleTick()
    }

    /// 剪贴板变更的提前唤醒：立即跑一次采集，不改轮询节奏
    ///
    /// 通知可能来自任意进程与线程，统一回主线程；changeCount 未变时 capture() 直接返回，
    /// 因此唤醒只可能「提前一点读到」，不会重复入库、也不会改变忽略判定。
    private func registerWakeObserver() {
        guard wakeObserver == nil else { return }
        wakeObserver = DistributedNotificationCenter.default().addObserver(
            forName: Self.pasteboardChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isRunning else { return }
                self.capture()
            }
        }
    }

    private func unregisterWakeObserver() {
        guard let wakeObserver else { return }
        DistributedNotificationCenter.default().removeObserver(wakeObserver)
        self.wakeObserver = nil
    }

    /// 日志用的秒数文案（一位小数，避免打印 0.5000000001 这类浮点尾数）
    private static func secondsText(_ interval: TimeInterval) -> String {
        String(format: "%.1f", interval)
    }

    /// 立即采集一次（分支 A 的面板打开 / 手动采集按钮；与轮询同一条流水线，无新内容时静默返回）
    public func captureNow() {
        capture()
    }

    // MARK: 采集流水线

    private func capture() {
        guard !isPaused, checkAccessBehavior() else { return }   // 暂停 = 不采（不只是不停轮询），captureNow 同样被挡
        let changeCount = pasteboard.changeCount
        // 第 5 节第 2 步：changeCount 未变立即返回，不读任何内容数据（含类型列表）
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        let typeNames = (pasteboard.types ?? []).map(\.rawValue)
        let source = sourceApplication()
        if let reason = ClipboardIgnorePolicy.ignoreReason(typeNames: typeNames,
                                                           bundleID: source?.bundleIdentifier,
                                                           blacklistedBundleIDs: preferences.ignoredBundleIDs) {
            logger.debug("剪贴板采集跳过：\(reason.label)")
            return
        }
        guard let resolution = makeDraft(source: source) else {
            logger.debug("剪贴板无可用内容（空内容 / 图片超限 / 无支持类型）")
            return
        }
        switch resolution {
        case .immediate(let draft):
            onCapture?(draft)
        case .deferred(let request):
            submitImage(request)
        }
    }

    /// 读取系统剪贴板访问行为；alwaysDeny 时停采并提示（不得静默）
    private func checkAccessBehavior() -> Bool {
        guard #available(macOS 15.4, *) else { return true }
        guard pasteboard.accessBehavior == .alwaysDeny else { return true }
        stop()
        onStateChange?(.denied(.alwaysDeny))
        logger.warning("剪贴板访问被系统拒绝：请前往「系统设置 → 隐私与安全性」允许本应用访问剪贴板")
        return false
    }

    /// 来源 App：前台应用即用户的复制来源；前台是本 App 时不记录来源（面板打开态的采集）
    private func sourceApplication() -> NSRunningApplication? {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return nil }
        if let ownBundleID = Bundle.main.bundleIdentifier, frontmost.bundleIdentifier == ownBundleID {
            return nil
        }
        return frontmost
    }

    // MARK: 内容解析（实现在 PasteboardWatcher+Images.swift）
}
